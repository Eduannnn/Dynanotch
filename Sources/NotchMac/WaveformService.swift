import Foundation
import CoreAudio
import Combine
import NotchCore

private final class SpectrumMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var bands = Array(repeating: 0.0, count: 6)
    private var snapshotTime: TimeInterval = 0
    private var analyzer = AudioSpectrum(sampleRate: 48_000)
    private var buffersReceived = 0
    private var framesReceived = 0
    private var peak = 0.0

    func configure(sampleRate: Double) {
        analyzer = AudioSpectrum(sampleRate: sampleRate)
        lock.lock(); bands = Array(repeating: 0, count: 6); buffersReceived = 0
        framesReceived = 0; peak = 0; snapshotTime = 0; lock.unlock()
    }
    func process(_ list: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first, let data = first.mData else { return }
        let interleavedChannels = max(1, Int(first.mNumberChannels))
        let frames = Int(first.mDataByteSize)/MemoryLayout<Float>.size/interleavedChannels
        guard frames > 0 else { return }
        let firstData = data.assumingMemoryBound(to: Float.self)
        let second = buffers.count > 1 && interleavedChannels == 1 ? buffers[1] : nil
        let secondData = second?.mData?.assumingMemoryBound(to: Float.self)
        let secondFrames = Int(second?.mDataByteSize ?? 0)/MemoryLayout<Float>.size
        let channels = interleavedChannels > 1 || secondData != nil ? 2 : 1
        var maximum = 0.0
        let result = analyzer.analyze(frameCount: frames, channels: channels) { frame, channel in
            let value: Float
            if interleavedChannels > 1 { value = firstData[frame*interleavedChannels+channel] }
            else if channel == 1, let secondData, frame < secondFrames { value = secondData[frame] }
            else { value = firstData[frame] }
            if value.isFinite { maximum = max(maximum, abs(Double(value))) }
            return value
        }
        lock.lock(); bands = result; snapshotTime = ProcessInfo.processInfo.systemUptime
        buffersReceived += 1; framesReceived += frames; peak = maximum; lock.unlock()
    }
    func read() -> [Double] {
        lock.lock(); defer { lock.unlock() }
        return ProcessInfo.processInfo.systemUptime-snapshotTime < 0.3 ? bands : Array(repeating: 0, count: 6)
    }
    func diagnostics() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["buffersReceived": buffersReceived, "framesReceived": framesReceived,
                "lastPCMAbsolutePeak": peak, "measuredBands": bands,
                "secondsSincePCM": snapshotTime > 0 ? ProcessInfo.processInfo.systemUptime-snapshotTime : -1]
    }
}

@MainActor final class WaveformService: ObservableObject {
    @Published private(set) var levels = [Double](repeating: 0, count: 6)
    @Published private(set) var active = false
    @Published private(set) var message = "Enable the live waveform to allow system audio access. Audio is analyzed in memory and never saved."
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var timer: Timer?
    private let meter = SpectrumMeter()
    private let queue = DispatchQueue(label: "com.eduannnn.notch.spectrum", qos: .userInteractive)

    func start() {
        guard !active else { return }
        guard #available(macOS 14.4, *) else { message = "The live waveform needs macOS 14.4 or later."; return }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Dynanotch live waveform"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { fail("Allow system audio recording in Privacy & Security, then enable the waveform again."); return }
        let format: AudioStreamBasicDescription = audioValue(tap, kAudioTapPropertyFormat, fallback: AudioStreamBasicDescription())
        guard format.mBitsPerChannel == 32, format.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { fail("This audio format cannot be visualized."); return }
        queue.sync { meter.configure(sampleRate: format.mSampleRate > 0 ? format.mSampleRate : 48_000) }
        let output: UInt32 = audioValue(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, fallback: 0)
        let uid = audioString(output, kAudioDevicePropertyDeviceUID) ?? ""
        guard !uid.isEmpty else { fail("No sound output is available."); return }
        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Dynanotch meter",
            kAudioAggregateDeviceUIDKey: "com.eduannnn.notch.meter.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            // Tap-only input: do not attach a microphone or alter the real output device.
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
        ]
        guard AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate) == noErr else { fail("Could not start the audio meter."); return }
        let meter = self.meter
        guard AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, queue, { _, input, _, _, _ in meter.process(input) }) == noErr,
              let ioProc, AudioDeviceStart(aggregate, ioProc) == noErr else { fail("The audio meter could not read this output."); return }
        active = true; message = "Live system audio waveform is enabled. Audio is never saved."
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let targets = self.meter.read()
                self.levels = zip(self.levels, targets).map { old, next in old + (next - old) * (next > old ? 0.70 : 0.28) }
            }
        }
        timer?.tolerance = 0.002
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if aggregate != 0, let ioProc { AudioDeviceStop(aggregate, ioProc); AudioDeviceDestroyIOProcID(aggregate, ioProc) }
        ioProc = nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
        active = false; levels = [0, 0, 0, 0, 0, 0]
    }
    var diagnostics: [String: Any] {
        var data = meter.diagnostics(); data["active"] = active; data["message"] = message; data["displayedBands"] = levels; return data
    }
    func restartIfActive() { if active { stop(); start() } }
    private func fail(_ text: String) { stop(); message = text }
}
