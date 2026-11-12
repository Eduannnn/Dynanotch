import AppKit
import CoreAudio
import Combine
import NotchCore

func audioAddress(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    .init(mSelector: selector, mScope: scope, mElement: element)
}

func audioValue<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, fallback: T) -> T {
    var address = audioAddress(selector, scope: scope, element: element)
    var value = fallback
    var size = UInt32(MemoryLayout<T>.size)
    let result = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
    return result == noErr ? value : fallback
}

func audioString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = audioAddress(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
}

struct AudioOutput: Identifiable, Hashable {
    var id: AudioObjectID
    var name: String
    var symbol: String
}

@MainActor final class AudioService: ObservableObject {
    @Published private(set) var volume: Double = 0
    @Published private(set) var muted = false
    @Published private(set) var canAdjust = false
    @Published private(set) var outputs: [AudioOutput] = []
    @Published private(set) var selectedDevice: AudioObjectID = 0
    @Published var message = ""
    var onVolumeChanged: ((Double, Bool) -> Void)?
    private var timer: Timer?
    private var ticks = 0
    private var initialized = false
    // A device can retain a nonzero scalar when mute is used to reach zero.
    private var zeroVolumeMuteReadback: Double?

    var volumeForStepping: Double {
        zeroVolumeMuteReadback == nil ? volume : 0
    }

    var symbol: String {
        muted || volume == 0 ? "speaker.slash.fill" : volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    func start() {
        refreshOutputs(); refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh(); self.ticks += 1
                if self.ticks % 12 == 0 { self.refreshOutputs() }
            }
        }
        timer?.tolerance = 0.08
    }

    private func volumeElement(_ device: AudioObjectID) -> AudioObjectPropertyElement? {
        for element: UInt32 in [0, 1] {
            var address = audioAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
            var settable: DarwinBoolean = false
            if AudioObjectHasProperty(device, &address), AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue { return element }
        }
        return nil
    }

    private func refresh() {
        let device: UInt32 = audioValue(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, fallback: 0)
        let changedDevice = selectedDevice != device
        if changedDevice { selectedDevice = device; initialized = false; refreshOutputs() }
        let element = volumeElement(device)
        let available = element != nil
        let value: Float32 = available ? audioValue(device, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element!, fallback: 0) : 1
        let mute: UInt32 = audioValue(device, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, fallback: 0)
        let newVolume = unit(Double(value)), newMuted = mute != 0
        if let zeroVolumeMuteReadback,
           changedDevice || !available || !newMuted || abs(newVolume - zeroVolumeMuteReadback) > 0.003 {
            self.zeroVolumeMuteReadback = nil
        }
        if initialized && (abs(volume - newVolume) > 0.002 || muted != newMuted) { onVolumeChanged?(newVolume, newMuted) }
        if volume != newVolume { volume = newVolume }
        if muted != newMuted { muted = newMuted }
        if canAdjust != available { canAdjust = available }
        initialized = true
    }

    func refreshNow() { refresh() }

    @discardableResult func setVolume(_ level: Double) -> Bool {
        guard canAdjust, let element = volumeElement(selectedDevice) else { return false }
        var value = Float32(unit(level))
        var address = audioAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
        var succeeded = AudioObjectSetPropertyData(selectedDevice, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
        if element == 1 {
            address.mElement = 2
            if AudioObjectHasProperty(selectedDevice, &address) {
                let rightSucceeded = AudioObjectSetPropertyData(selectedDevice, &address, 0, nil,
                    UInt32(MemoryLayout<Float32>.size), &value) == noErr
                succeeded = succeeded || rightSucceeded
            }
        }
        refresh()
        if value == 0 {
            // Some outputs clamp the scalar above zero. Mute is a second way to reach silence.
            let didMute = muted ? false : setMuted(true)
            if muted || didMute {
                zeroVolumeMuteReadback = volume > 0 ? volume : nil
                message = ""
            }
            return succeeded || didMute || muted
        }
        guard succeeded else { message = "This output controls its own volume."; return false }
        message = ""
        if muted { _ = setMuted(false) }
        // An accepted write owns this keypress even if the device reports it later.
        return true
    }

    @discardableResult func setMuted(_ value: Bool) -> Bool {
        var raw: UInt32 = value ? 1 : 0
        var address = audioAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectSetPropertyData(selectedDevice, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &raw) == noErr else { message = "Mute is unavailable for this output."; return false }
        refresh()
        message = ""
        return true
    }

    func selectOutput(_ id: AudioObjectID) {
        guard outputs.contains(where: { $0.id == id }) else { return }
        var selected = id
        var address = audioAddress(kAudioHardwarePropertyDefaultOutputDevice)
        if AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &selected) != noErr { message = "Could not switch the sound output." }
        refresh()
    }

    private func refreshOutputs() {
        var address = audioAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { return }
        let result: [AudioOutput] = ids.compactMap { id in
            var stream = audioAddress(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &stream, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
            let name = audioString(id, kAudioObjectPropertyName) ?? "Audio output"
            if name.hasPrefix("Dynanotch") { return nil }
            let lower = name.lowercased()
            let symbol = lower.contains("airpod") ? "airpodspro" : lower.contains("head") ? "headphones" : lower.contains("display") || lower.contains("hdmi") ? "display" : "hifispeaker.fill"
            return AudioOutput(id: id, name: name, symbol: symbol)
        }
        if result != outputs { outputs = result }
    }
}

/// Uses the system DisplayServices bridge on supported built-in displays. No helper or driver is installed.
/// The API is private, so this adapter is optional and always checks availability at runtime.
@MainActor final class BrightnessService: ObservableObject {
    typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    @Published private(set) var level: Double = 0.5
    @Published private(set) var available = false
    private var handle: UnsafeMutableRawPointer?
    private var get: GetBrightness?
    private var set: SetBrightness?
    private var timer: Timer?
    private var initialized = false
    private var display: UInt32 = 0
    var onChanged: ((Double) -> Void)?

    init() {
        handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        if let handle, let g = dlsym(handle, "DisplayServicesGetBrightness"), let s = dlsym(handle, "DisplayServicesSetBrightness") {
            get = unsafeBitCast(g, to: GetBrightness.self); set = unsafeBitCast(s, to: SetBrightness.self)
        }
    }
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        timer?.tolerance = 0.1
    }
    func useDisplay(_ id: UInt32) { if display != id { display = id; initialized = false; refresh() } }
    private func refresh() {
        let target = display == 0 ? CGMainDisplayID() : display
        var value: Float = 0
        let supported = get?(target, &value) == 0 && CGDisplayIsBuiltin(target) != 0
        if available != supported { available = supported }
        guard supported else { return }
        let next = unit(Double(value))
        if initialized && abs(next - level) > 0.003 { onChanged?(next) }
        if level != next { level = next }
        initialized = true
    }
    func refreshNow() { refresh() }
    @discardableResult func adjust(_ value: Double) -> Bool {
        guard available else { return false }
        let target = max(0.01, unit(value))
        guard set?(display == 0 ? CGMainDisplayID() : display, Float(target)) == 0 else { return false }
        refresh()
        return true
    }
}
