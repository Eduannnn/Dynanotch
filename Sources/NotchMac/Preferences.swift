import AppKit
import SwiftUI

@MainActor final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var showOnLockScreen: Bool { didSet { defaults.set(showOnLockScreen, forKey: "showOnLockScreen") } }
    @Published var hideMenuBarIcon: Bool { didSet { defaults.set(hideMenuBarIcon, forKey: "hideMenuBarIcon") } }
    @Published var liquidGlass: Bool { didSet { defaults.set(liquidGlass, forKey: "liquidGlass") } }
    @Published var previewPeek: Bool { didSet { defaults.set(previewPeek, forKey: "previewPeek") } }
    @Published var artworkTint: Bool { didSet { defaults.set(artworkTint, forKey: "artworkTint") } }
    @Published var showNotices: Bool { didSet { defaults.set(showNotices, forKey: "showNotices") } }
    @Published var showOSD: Bool { didSet { defaults.set(showOSD, forKey: "showOSD") } }
    @Published var replaceSystemHUD: Bool { didSet { defaults.set(replaceSystemHUD, forKey: "replaceSystemHUD") } }
    @Published var waveformEnabled: Bool { didSet { defaults.set(waveformEnabled, forKey: "waveformEnabled") } }
    @Published var manualGeometry: Bool { didSet { defaults.set(manualGeometry, forKey: "manualGeometry") } }
    @Published var cameraWidth: Double { didSet { defaults.set(cameraWidth, forKey: "cameraWidth") } }
    @Published var cameraHeight: Double { didSet { defaults.set(cameraHeight, forKey: "cameraHeight") } }
    @Published var horizontalOffset: Double { didSet { defaults.set(horizontalOffset, forKey: "horizontalOffset") } }
    @Published var selectedDisplay: UInt32 { didSet { defaults.set(Int(selectedDisplay), forKey: "selectedDisplay") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults
        func flag(_ key: String, fallback: Bool = true) -> Bool { stored.object(forKey: key) as? Bool ?? fallback }
        showOnLockScreen = flag("showOnLockScreen")
        hideMenuBarIcon = flag("hideMenuBarIcon", fallback: false)
        liquidGlass = flag("liquidGlass", fallback: false)
        previewPeek = flag("previewPeek", fallback: false)
        artworkTint = flag("artworkTint")
        showNotices = flag("showNotices")
        showOSD = flag("showOSD")
        replaceSystemHUD = flag("replaceSystemHUD")
        waveformEnabled = flag("waveformEnabled", fallback: false)
        manualGeometry = flag("manualGeometry", fallback: false)
        cameraWidth = defaults.object(forKey: "cameraWidth") as? Double ?? 180
        cameraHeight = defaults.object(forKey: "cameraHeight") as? Double ?? 32
        horizontalOffset = defaults.object(forKey: "horizontalOffset") as? Double ?? 0
        selectedDisplay = UInt32(clamping: defaults.integer(forKey: "selectedDisplay"))
    }

    func resetGeometry() {
        manualGeometry = false; cameraWidth = 180; cameraHeight = 32; horizontalOffset = 0
    }
}

struct DisplayGeometry {
    let screen: NSScreen
    let cameraWidth: CGFloat
    let cameraHeight: CGFloat
    let centerX: CGFloat
    var hasHardwareNotch: Bool { screen.safeAreaInsets.top > 0 }

    private static func inferredNotchHeight(on screen: NSScreen) -> CGFloat? {
        if screen.safeAreaInsets.top > 0 { return screen.safeAreaInsets.top }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        // A virtual display can report the taller menu bar without a camera safe area.
        return (34...43).contains(menuBarHeight) ? menuBarHeight : nil
    }

    @MainActor static func resolve(_ preferences: Preferences) -> DisplayGeometry? {
        let screens = NSScreen.screens
        let preferred = screens.first { $0.displayID == preferences.selectedDisplay }
        let notched = screens.first { $0.safeAreaInsets.top > 0 }
        let builtIn = screens.first { CGDisplayIsBuiltin($0.displayID) != 0 }
        let primary = screens.first { $0.displayID == CGMainDisplayID() }
        guard let screen = preferred ?? notched ?? builtIn ?? primary ?? screens.first else { return nil }
        let leftWidth = screen.auxiliaryTopLeftArea?.width
        let rightWidth = screen.auxiliaryTopRightArea?.width
        let detectedWidth = leftWidth.flatMap { left in rightWidth.map { screen.frame.width - left - $0 } } ?? 180
        let width = screen.safeAreaInsets.top <= 0 ? 18 : preferences.manualGeometry ? min(400, max(100, preferences.cameraWidth)) : max(100, detectedWidth)
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let automaticHeight = screen.safeAreaInsets.top <= 0 ? 28 : inferredNotchHeight(on: screen) ?? ((20...30).contains(menuBarHeight) ? menuBarHeight : 24)
        let height = screen.safeAreaInsets.top <= 0 ? 28 : preferences.manualGeometry ? min(64, max(screen.safeAreaInsets.top, preferences.cameraHeight)) : automaticHeight
        let center = leftWidth.map { screen.frame.minX + $0 + detectedWidth / 2 } ?? screen.frame.midX
        let offset = preferences.manualGeometry ? min(240, max(-240, preferences.horizontalOffset)) : 0
        return .init(screen: screen, cameraWidth: width, cameraHeight: height, centerX: center + offset)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}

extension Color {
    static let notchSurface = Color.black
    static let notchAccent = Color(red: 0.286, green: 1, blue: 0.996)
    static let notchSecondary = Color(red: 0.62, green: 0.63, blue: 0.69)
    static let notchTile = Color(red: 39.0 / 255, green: 39.0 / 255, blue: 43.0 / 255)
}
