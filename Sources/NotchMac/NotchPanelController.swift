import AppKit
import SwiftUI
import Combine
import NotchCore

final class NotchPanel: NSPanel {
    var onEscape: (() -> Void)?
    var acceptsKeyboard = true
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor final class NotchPanelController {
    let model: NotchModel
    private(set) var panel: NotchPanel
    private var subscriptions = Set<AnyCancellable>()
    private var pointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var screenObserver: Any?
    private var outsideMonitor: Any?
    private var keyMonitor: Any?
    private var lockObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var unlockWatchdog: Timer?
    private var geometry: DisplayGeometry?

    init(model: NotchModel) {
        self.model = model
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.canBecomeVisibleWithoutLogin = model.preferences.showOnLockScreen
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true
        panel.onEscape = { [weak model] in model?.close() }
        let host = NSHostingView(rootView: NotchRootView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        updateDisplay()
        model.preferences.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateDisplay(); self?.applyWindowState() }
        }.store(in: &subscriptions)
        model.onSurfaceChanged = { [weak self] in self?.trackPointer() }
        model.$hidden.sink { [weak self] hidden in
            guard let self else { return }
            self.applyWindowState(hidden: hidden)
        }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateDisplay()
                self?.applyWindowState()
            }
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.model.screenLocked else { return }
            let point = NSEvent.mouseLocation
            if !self.isOverAirPodsSatellite(point) { self.model.closeAirPodsDetails() }
            if !self.isInteractive(point) { self.model.close() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard self?.model.screenLocked != true else { return event }
            if let self, isNotchSettingsShortcut(characters: event.charactersIgnoringModifiers,
                command: event.modifierFlags.contains(.command), shift: event.modifierFlags.contains(.shift),
                option: event.modifierFlags.contains(.option), control: event.modifierFlags.contains(.control),
                overNotch: self.panel.isKeyWindow || self.isPointerOverNotch) {
                self.model.openSettings?(); return nil
            }
            if event.keyCode == 53 { self?.model.close(); return nil }
            return event
        }
        // Pointer events and animated frame changes replace the old always-running 60 ms poll.
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            self?.trackPointer()
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown]) { [weak self] event in
            if let self, event.type == .leftMouseDown, !self.isOverAirPodsSatellite(NSEvent.mouseLocation) {
                self.model.closeAirPodsDetails()
            }
            self?.trackPointer()
            return event
        }
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setScreenLocked(locked) }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let locked = Self.sessionIsLocked else { return }
                    self.setScreenLocked(locked)
                }
            })
        }
        setScreenLocked(Self.sessionIsLocked ?? false)
    }

    private static var sessionIsLocked: Bool? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private func setScreenLocked(_ locked: Bool) {
        if locked != model.screenLocked {
            if locked {
                model.lockEventCount += 1
                panel.ignoresMouseEvents = true
                panel.acceptsKeyboard = false
                panel.resignKey()
                model.closeAirPodsDetails()
                model.edgeLighting = EdgeLighting()
                model.bubbleLighting = EdgeLighting()
            }
            model.screenLocked = locked
            model.mediaKeys.suspendForLockScreen(locked)
        }
        if locked && unlockWatchdog == nil {
            // Recover if the distributed unlock notification is dropped.
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    if Self.sessionIsLocked == false { self?.setScreenLocked(false) }
                }
            }
            timer.tolerance = 0.25
            RunLoop.main.add(timer, forMode: .common)
            unlockWatchdog = timer
        } else if !locked {
            unlockWatchdog?.invalidate()
            unlockWatchdog = nil
        }
        applyWindowState()
        if !locked { trackPointer() }
    }

    private func applyWindowState(hidden: Bool? = nil) {
        let locked = model.screenLocked
        let showOnLockScreen = model.preferences.showOnLockScreen
        let shouldShow = !(hidden ?? model.hidden) && (!locked || showOnLockScreen)
        panel.canBecomeVisibleWithoutLogin = showOnLockScreen
        panel.acceptsKeyboard = !locked
        if locked { panel.ignoresMouseEvents = true }
        if !shouldShow { panel.orderOut(nil) }
        panel.level = locked && shouldShow
            ? NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            : NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        model.configuredVisibleWithoutLogin = panel.canBecomeVisibleWithoutLogin
        model.configuredWindowLevel = panel.level.rawValue
        if locked { model.lastLockedWindowLevel = panel.level.rawValue }
        if shouldShow, geometry != nil { panel.orderFrontRegardless() }
    }

    func updateDisplay() {
        guard let geometry = DisplayGeometry.resolve(model.preferences) else {
            self.geometry = nil
            panel.orderOut(nil)
            return
        }
        self.geometry = geometry
        model.displayScreen = geometry.screen
        model.cameraWidth = geometry.cameraWidth
        model.cameraHeight = geometry.cameraHeight
        model.availableWidth = geometry.screen.frame.width
        model.brightness.useDisplay(geometry.screen.displayID)
        let frame = NSRect(x: geometry.centerX - NotchRootView.canvasWidth / 2, y: geometry.screen.frame.maxY - NotchRootView.canvasHeight, width: NotchRootView.canvasWidth, height: NotchRootView.canvasHeight)
        panel.setFrame(frame, display: true)
    }

    private var bodyRect: NSRect {
        let surface = model.presentedSurface ?? model.surfaceTarget
        return NSRect(x: panel.frame.midX - surface.width / 2 + surface.offset,
                      y: panel.frame.maxY - surface.height, width: surface.width, height: surface.height)
    }
    private func satelliteRect(_ satellite: NotchSatellite) -> NSRect? {
        guard let rect = model.presentedSatellites[satellite], !rect.isEmpty else { return nil }
        return NSRect(x: panel.frame.minX + rect.minX, y: panel.frame.maxY - rect.maxY,
                      width: rect.width, height: rect.height)
    }

    private func isOverSatellite(_ satellite: NotchSatellite, point: NSPoint) -> Bool {
        guard !model.hidden, !model.screenLocked, !isBodyInteractive(point),
              let rect = satelliteRect(satellite) else { return false }
        // During a merge the satellite is drawn beneath the camera and main island.
        if hardwareObstruction?.contains(point) == true { return false }
        let radius = rect.height / 2
        let dx = max(0, abs(point.x - rect.midX) - (rect.width / 2 - radius))
        return hypot(dx, point.y - rect.midY) <= radius
    }

    private func isOverAirPodsSatellite(_ point: NSPoint) -> Bool {
        model.leadingAirPods != nil && isOverSatellite(.airPods, point: point)
    }

    private func isInteractive(_ point: NSPoint) -> Bool {
        if model.hidden || model.screenLocked { return false }
        return isBodyInteractive(point) || isOverAirPodsSatellite(point)
            || (model.showsMediaBubble && isOverSatellite(.music, point: point))
    }

    private var hardwareObstruction: CGRect? {
        guard let geometry, geometry.hasHardwareNotch else { return nil }
        return CGRect(x: geometry.centerX - geometry.cameraWidth / 2,
                      y: geometry.screen.frame.maxY - geometry.cameraHeight,
                      width: geometry.cameraWidth, height: geometry.cameraHeight)
    }

    private func isBodyInteractive(_ point: NSPoint) -> Bool {
        if model.hidden || model.screenLocked { return false }
        guard geometry != nil, hardwareObstruction?.contains(point) != true else { return false }
        let surface = model.presentedSurface ?? model.surfaceTarget
        let local = CGPoint(x: point.x-bodyRect.minX+surface.ear, y: bodyRect.maxY-point.y)
        return NotchSilhouette(radius: surface.radius, ear: surface.ear)
            .path(in: CGRect(x: 0, y: 0, width: surface.width+2*surface.ear, height: surface.height)).contains(local)
    }
    var isPointerOverNotch: Bool {
        guard !model.hidden, !model.screenLocked else { return false }
        // Keyboard shortcuts also work over the physical camera obstruction,
        // which deliberately remains excluded from mouse hit testing.
        return bodyRect.contains(NSEvent.mouseLocation) || isInteractive(NSEvent.mouseLocation)
    }
    private func trackPointer() {
        guard !model.screenLocked else { panel.ignoresMouseEvents = true; return }
        let point = NSEvent.mouseLocation
        let interactive = isInteractive(point)
        let body = bodyRect
        let lighting = model.hidden ? EdgeLighting() : EdgeLighting.response(to: point, around: body)
        func lightingForSatellite(_ satellite: NotchSatellite) -> EdgeLighting {
            guard !model.hidden, let rect = satelliteRect(satellite) else { return EdgeLighting() }
            return EdgeLighting.response(to: point, around: rect, reach: 80)
        }
        let bubbleLighting = lightingForSatellite(.music)
        let airPodsLighting = lightingForSatellite(.airPods)
        let chargeLighting = lightingForSatellite(.charge)
        let pillLighting = lightingForSatellite(.volume)
        func changed(_ old: EdgeLighting, _ new: EdgeLighting) -> Bool {
            abs(old.point.x - new.point.x) > 0.005 || abs(old.point.y - new.point.y) > 0.005
                || abs(old.strength - new.strength) > 0.01
        }
        if changed(model.edgeLighting, lighting) { model.edgeLighting = lighting }
        if changed(model.bubbleLighting, bubbleLighting) { model.bubbleLighting = bubbleLighting }
        if changed(model.airPodsPillLighting, airPodsLighting) { model.airPodsPillLighting = airPodsLighting }
        if changed(model.chargePillLighting, chargeLighting) { model.chargePillLighting = chargeLighting }
        if changed(model.volumePillLighting, pillLighting) { model.volumePillLighting = pillLighting }
        // Proximity only affects lighting. It never expands the interactive region.
        model.pointerIsInteractive = interactive
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
        let inMedia = isBodyInteractive(point) || (!model.hidden && model.hovering && bodyRect.insetBy(dx: -6, dy: -6).contains(point))
        model.setHover(inMedia)
    }
    func stop() {
        lockObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        lockObservers.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        unlockWatchdog?.invalidate()
        unlockWatchdog = nil
        model.onSurfaceChanged = nil
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panel.orderOut(nil)
    }
}
