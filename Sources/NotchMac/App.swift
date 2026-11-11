import AppKit
import SwiftUI
import ApplicationServices
import Combine
import Darwin

@main enum DynanotchMain {
    @MainActor static func main() {
        guard AppRestart.waitForPriorInstance(arguments: ProcessInfo.processInfo.arguments) else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private static let airPodsPreviewRequest = Notification.Name("com.eduannnn.quickshell-notch.mac.previewAirPods")
    private lazy var model = NotchModel()
    private var verificationOnly = false
    private var notch: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var diagnosticObserver: NSObjectProtocol?
    private var previewObserver: NSObjectProtocol?
    private var menuVisibility: AnyCancellable?
    private var restarting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--verify-native-skips"), args.indices.contains(index + 1) {
            verificationOnly = true; AppVerification.runNativeSkips(directory: args[index + 1]); return
        }
        if let index = args.firstIndex(of: "--check-artwork-colors"), args.indices.contains(index + 1) {
            verificationOnly = true
            if let image = NSImage(contentsOfFile: args[index + 1]) {
                let (primary, secondary) = MediaService.palette(image)
                let report = ["primary": [primary.r, primary.g, primary.b], "secondary": [secondary.r, secondary.g, secondary.b]]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    print(String(decoding: data, as: UTF8.self))
                }
            }
            NSApp.terminate(nil); return
        }
        if let index = args.firstIndex(of: "--verify-visuals"), args.indices.contains(index + 1) {
            verificationOnly = true; AppVerification.runVisual(directory: args[index + 1]); return
        }
        if let index = args.firstIndex(of: "--verify-app"), args.indices.contains(index + 1) {
            verificationOnly = true
            AppVerification.run(directory: args[index + 1]); return
        }
        if args.contains("--check-airpods-assets") {
            Task { @MainActor in
                let report = await SystemAirPodsArtwork.diagnostic()
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
                NSApp.terminate(nil)
            }
            return
        }
        if let index = args.firstIndex(of: "--export-previews"), args.indices.contains(index + 1) {
            Task { @MainActor in
                await SystemAirPodsArtwork.preload()
                PreviewExporter.export(model: model, directory: args[index + 1])
                NSApp.terminate(nil)
            }
            return
        }
        if args.contains("--check-hud") {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.eduannnn.quickshell-notch.mac").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated && kill($0.processIdentifier, 0) == 0 }
            if !others.isEmpty {
                if !HUDDiagnostics.queryRunning() { print("The running app did not reply to the HUD status request.") }
                NSApp.terminate(nil); return
            }
            model.mediaKeys.configure(enabled: true); model.mediaKeys.start()
            let report: [String: Any] = [
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "accessibilityGranted": AXIsProcessTrusted(),
                "keyTakeoverActive": model.mediaKeys.status == .active,
                "tapLocation": model.mediaKeys.tapLocation,
                "status": model.mediaKeys.message
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
            model.mediaKeys.stop(); NSApp.terminate(nil)
            return
        }
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.eduannnn.quickshell-notch.mac").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated && kill($0.processIdentifier, 0) == 0 }
        if args.contains("--preview-airpods"), !existing.isEmpty {
            verificationOnly = true
            DistributedNotificationCenter.default().postNotificationName(Self.airPodsPreviewRequest, object: nil, userInfo: nil, deliverImmediately: true)
            print("Requested AirPods Pro connection preview with sample 75% battery.")
            NSApp.terminate(nil); return
        }
        guard existing.isEmpty || args.contains("--allow-duplicate") else { existing.first?.activate(options: []); NSApp.terminate(nil); return }
        model.openSettings = { [weak self] in self?.showSettings() }
        model.restartApp = { [weak self] in self?.restartDynanotch() }
        model.mediaKeys.settingsShortcut = { [weak self] in
            guard let self, self.notch?.isPointerOverNotch == true else { return false }
            // Return from the event filter before creating/activating a SwiftUI settings window.
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
            return true
        }
        setupMenu()
        notch = NotchPanelController(model: model)
        model.start(demo: args.contains("--demo"))
        previewObserver = DistributedNotificationCenter.default().addObserver(forName: Self.airPodsPreviewRequest, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.previewNotice() }
        }
        diagnosticObserver = DistributedNotificationCenter.default().addObserver(forName: HUDDiagnostics.request, object: nil, queue: .main) { [weak self] notification in
            guard let nonce = notification.userInfo?["nonce"] as? String, UUID(uuidString: nonce) != nil else { return }
            MainActor.assumeIsolated { if let self { HUDDiagnostics.write(model: self.model, nonce: nonce) } }
        }
        HUDDiagnostics.write(model: model, nonce: "startup")
        if args.contains("--expanded") { model.peek = false; model.hovering = true; model.pinned = true }
        if args.contains("--timer") { newTimer() }
        if args.contains("--enable-waveform") { model.preferences.waveformEnabled = true }
        if args.contains("--preview-airpods") { previewNotice() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !verificationOnly else { return }
        if let previewObserver { DistributedNotificationCenter.default().removeObserver(previewObserver) }
        notch?.stop(); model.stop()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }

    private func setupMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "macbook.gen2", accessibilityDescription: "Dynanotch")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Dynanotch"
        let menu = NSMenu()
        func add(_ title: String, _ selector: Selector, _ symbol: String, key: String = "") {
            let row = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            row.target = self; row.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); menu.addItem(row)
        }
        add("Settings…", #selector(showSettings), "gearshape", key: ",")
        add("New Timer…", #selector(newTimer), "timer", key: "t")
        menu.addItem(.separator())
        add("Enable HUD Replacement…", #selector(enableHUDReplacement), "keyboard")
        add("Preview Player", #selector(togglePreview), "music.note")
        add("Preview Device Notice", #selector(previewNotice), "airpodspro")
        add("Preview Charging", #selector(previewPower), "bolt.fill")
        add("Hide Notch", #selector(toggleHidden), "eye.slash")
        add("Hide Menu Bar Icon", #selector(hideMenuIcon), "menubar.rectangle")
        menu.addItem(.separator())
        add("Restart Dynanotch", #selector(restartDynanotch), "arrow.clockwise")
        add("Quit Dynanotch", #selector(quit), "xmark.circle", key: "q")
        item.menu = menu; statusItem = item
        menuVisibility = model.preferences.$hideMenuBarIcon.sink { [weak item] hidden in item?.isVisible = !hidden }
        let main = NSMenu()
        let appMenuItem = NSMenuItem(); main.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Dynanotch")
        for (title, action, key) in [("Settings…", #selector(showSettings), ","), ("Restart Dynanotch", #selector(restartDynanotch), ""), ("Quit Dynanotch", #selector(quit), "q")] {
            let row = NSMenuItem(title: title, action: action, keyEquivalent: key); row.target = self; appMenu.addItem(row)
        }
        appMenuItem.submenu = appMenu; NSApp.mainMenu = main
    }

    @objc private func enableHUDReplacement() {
        model.preferences.showOSD = true; model.preferences.replaceSystemHUD = true
        model.mediaKeys.requestAccess()
    }
    @objc private func togglePreview() { model.setPreview(!model.previewMode) }
    @objc private func newTimer() { model.settingsTab = .activities; showSettings() }
    @objc private func previewNotice() {
        Task { @MainActor [weak self] in
            _ = await SystemAirPodsArtwork.poster(for: .airpodsPro)
            self?.model.previewNotice()
        }
    }
    @objc private func previewPower() { model.previewCharging() }
    @objc private func toggleHidden() { model.hidden.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func hideMenuIcon() { model.preferences.hideMenuBarIcon = true }
    @objc private func restartDynanotch() {
        guard !restarting else { return }
        restarting = true
        do { try AppRestart.launchReplacement(); NSApp.terminate(nil) }
        catch { restarting = false; model.system.message = "Dynanotch could not restart: \(error.localizedDescription)" }
    }

    @objc func showSettings() {
        model.calibrating = false
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 602, height: 522), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Dynanotch Settings"
            window.contentView = NSHostingView(rootView: SettingsView(model: model, preferences: model.preferences, waveform: model.waveform, media: model.media))
            window.isReleasedWhenClosed = false
            window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(enableHUDReplacement) {
            let active = model.mediaKeys.status == .active
            menuItem.title = active ? "HUD Replacement Enabled" : "Enable HUD Replacement…"
            menuItem.state = active ? .on : .off
            return !active
        }
        if menuItem.action == #selector(togglePreview) { menuItem.state = model.previewMode ? .on : .off }
        if menuItem.action == #selector(toggleHidden) { menuItem.title = model.hidden ? "Show Notch" : "Hide Notch" }
        return true
    }
}
