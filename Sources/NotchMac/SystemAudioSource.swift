import AppKit
import CoreAudio

/// Public Core Audio process activity. This identifies the source, not a browser's private tabs.
struct SystemAudioSource: Sendable {
    var bundleID: String
    var name: String
    private static let browsers: [(String, String)] = [
        ("com.apple.Safari", "Safari"), ("com.google.Chrome", "Chrome"),
        ("net.imput.helium", "Helium"),
        ("org.chromium.Chromium", "Chromium"), ("com.brave.Browser", "Brave"),
        ("com.microsoft.edgemac", "Edge"), ("org.mozilla.firefox", "Firefox"),
        ("company.thebrowser.Browser", "Arc"), ("company.thebrowser.dia", "Dia"),
        ("com.vivaldi.Vivaldi", "Vivaldi"), ("com.operasoftware.Opera", "Opera"),
        ("org.mozilla.zen", "Zen"), ("com.kagi.kagimacOS", "Orion")
    ]
    static func activeBrowser() -> SystemAudioSource? {
        var address = audioAddress(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var processes = Array(repeating: AudioObjectID(0), count: Int(size)/MemoryLayout<AudioObjectID>.size)
        let status = processes.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { return nil }
        for process in processes {
            let running: UInt32 = audioValue(process, kAudioProcessPropertyIsRunningOutput, fallback: 0)
            guard running != 0, let bundle = audioString(process, kAudioProcessPropertyBundleID) else { continue }
            if let (root, name) = browsers.first(where: { bundle == $0.0 || bundle.hasPrefix($0.0 + ".") }) {
                return .init(bundleID: root, name: name)
            }
            if bundle.hasPrefix("com.apple.WebKit.") { return .init(bundleID: bundle, name: "Web audio") }
        }
        return nil
    }
    @MainActor func snapshot(reusing previous: MediaSnapshot? = nil) -> MediaSnapshot {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let cached = previous?.isBrowserAudio == true && previous?.bundleID == bundleID ? previous?.artwork : nil
        let icon = cached ?? url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "globe", accessibilityDescription: "Web audio")
        var result = MediaSnapshot(identity: .init(source: name, identifier: "system-audio/" + bundleID,
            title: "Browser audio", artist: name), bundleID: bundleID, source: name,
            duration: 0, position: 0, isPlaying: true, artwork: icon)
        result.canControl = false; result.isBrowserAudio = true
        if let icon { (result.tint, result.secondaryTint) = MediaService.palette(icon) }
        return result
    }
}
