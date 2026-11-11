import AppKit
import ApplicationServices

/// Query the running GUI process, rather than attributing a separate command-line probe's TCC state to it.
@MainActor enum HUDDiagnostics {
    static let request = Notification.Name("com.eduannnn.quickshell-notch.mac.requestHUDStatus")
    static var replyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dynanotch/HUDStatus.json")
    }
    static func write(model: NotchModel, nonce: String) {
        let report: [String: Any] = [
            "nonce": nonce, "pid": ProcessInfo.processInfo.processIdentifier,
            "appPath": Bundle.main.bundleURL.path,
            "accessibilityGranted": AXIsProcessTrusted(),
            "keyTakeoverActive": model.mediaKeys.status == .active,
            "tapLocation": model.mediaKeys.tapLocation,
            "menuBarIconHidden": model.preferences.hideMenuBarIcon,
            "batteryLevel": model.system.state.battery.map { $0 as Any } ?? NSNull(),
            "wifiOn": model.system.state.wifiOn,
            "networkConnected": model.system.state.networkConnected,
            "settingsShortcutHasAccessibility": AXIsProcessTrusted(),
            "status": model.mediaKeys.message,
            "waveformEnabled": model.preferences.waveformEnabled,
            "mediaPlaying": model.media.snapshot?.isPlaying ?? false,
            "presentation": String(describing: model.presentation),
            "notice": model.notices.current?.key ?? "none",
            "activityBubble": model.bubbleActivity?.rawValue ?? "none",
            "screenLocked": model.screenLocked,
            "showOnLockScreen": model.preferences.showOnLockScreen,
            "visibleWithoutLoginConfigured": model.configuredVisibleWithoutLogin,
            "windowLevel": model.configuredWindowLevel,
            "lockEventCount": model.lockEventCount,
            "lastLockedWindowLevel": model.lastLockedWindowLevel.map { $0 as Any } ?? NSNull(),
            "musicFavoriteAvailable": model.media.snapshot?.canFavorite ?? false,
            "musicFavorited": model.media.snapshot?.isFavorited.map { $0 as Any } ?? NSNull(),
            "mediaTitle": model.media.snapshot?.identity.title ?? "",
            "mediaArtworkReady": model.media.snapshot?.artwork != nil,
            "playbackNotifications": model.media.playbackNotificationCount,
            "mediaSource": model.media.snapshot?.source ?? "none",
            "browserAudio": model.media.snapshot?.isBrowserAudio ?? false,
            "artworkTint": model.media.snapshot.map { [$0.tint.r, $0.tint.g, $0.tint.b] } ?? [],
            "edgeLighting": ["x": model.edgeLighting.point.x, "y": model.edgeLighting.point.y, "strength": model.edgeLighting.strength],
            "bubbleLighting": ["x": model.bubbleLighting.point.x, "y": model.bubbleLighting.point.y, "strength": model.bubbleLighting.strength],
            "pointerInteractive": model.pointerIsInteractive,
            "audio": model.waveform.diagnostics,
            "artworkTurns": model.artworkTurns,
            "artworkTurnPhase": model.artworkTurnPhase,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        ]
        try? FileManager.default.createDirectory(at: replyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: replyURL, options: .atomic) }
    }
    static func queryRunning() -> Bool {
        let nonce = UUID().uuidString
        DistributedNotificationCenter.default().postNotificationName(request, object: nil, userInfo: ["nonce": nonce], deliverImmediately: true)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let data = try? Data(contentsOf: replyURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["nonce"] as? String == nonce,
               let text = String(data: data, encoding: .utf8) { print(text); return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    }
}
