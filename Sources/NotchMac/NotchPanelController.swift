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
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.updateDisplay() } }
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
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        setScreenLocked(session?["CGSSessionScreenIsLocked"] as? Bool ?? false)
    }

    private func setScreenLocked(_ locked: Bool) {
        if locked && !model.screenLocked { model.lockEventCount += 1 }
        model.screenLocked = locked
        if locked {
            model.closeAirPodsDetails()
            model.edgeLighting = EdgeLighting(); model.bubbleLighting = EdgeLighting()
            panel.resignKey()
        }
        applyWindowState()
    }
    private func applyWindowState(hidden: Bool? = nil) {
        panel.canBecomeVisibleWithoutLogin = model.preferences.showOnLockScreen
        panel.level = model.screenLocked && model.preferences.showOnLockScreen
            ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            : NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.acceptsKeyboard = !model.screenLocked
        model.configuredVisibleWithoutLogin = panel.canBecomeVisibleWithoutLogin
        model.configuredWindowLevel = panel.level.rawValue
        if model.screenLocked { model.lastLockedWindowLevel = panel.level.rawValue }
        if model.screenLocked { panel.ignoresMouseEvents = true }
        if (hidden ?? model.hidden) || (model.screenLocked && !model.preferences.showOnLockScreen) {
            panel.orderOut(nil)
        } else { panel.orderFrontRegardless() }
    }

    func updateDisplay() {
        guard let geometry = DisplayGeometry.resolve(model.preferences) else { panel.orderOut(nil); return }
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
    private var activityBubbleRect: NSRect {
        NSRect(x: bodyRect.minX - 42,
               y: panel.frame.maxY - max(0, (model.collapsedHeight - 34) / 2) - 34,
               width: 34, height: 34)
    }
    private var airPodsSatelliteRect: NSRect {
        let size = NotchModel.airPodsPillSize
        let width = model.airPodsSatelliteWidth
        return NSRect(x: bodyRect.minX - model.airPodsPillOffset + size - width,
                      y: activityBubbleRect.minY, width: width, height: size)
    }

    private func isOverAirPodsSatellite(_ point: NSPoint) -> Bool {
        guard !model.hidden, !model.screenLocked, model.leadingAirPods != nil else { return false }
        let rect = airPodsSatelliteRect
        let radius = rect.height / 2
        let dx = max(0, abs(point.x - rect.midX) - (rect.width / 2 - radius))
        return hypot(dx, point.y - rect.midY) <= radius
    }

    private func isInteractive(_ point: NSPoint) -> Bool {
        if model.hidden || model.screenLocked { return false }
        if isOverAirPodsSatellite(point) { return true }
        if model.showsMediaBubble,
           hypot(point.x - activityBubbleRect.midX, point.y - activityBubbleRect.midY) <= 17 { return true }
        return isBodyInteractive(point)
    }
    private func isBodyInteractive(_ point: NSPoint) -> Bool {
        if model.hidden || model.screenLocked { return false }
        guard let geometry else { return false }
        let obstruction = CGRect(x: geometry.centerX - geometry.cameraWidth/2,
                                 y: geometry.screen.frame.maxY-geometry.cameraHeight,
                                 width: geometry.cameraWidth, height: geometry.cameraHeight)
        if geometry.hasHardwareNotch && obstruction.contains(point) { return false }
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
        let bubble = activityBubbleRect
        let lighting = model.hidden ? EdgeLighting() : EdgeLighting.response(to: point, around: body)
        let bubbleLighting = model.hidden || !model.showsMediaBubble ? EdgeLighting()
            : EdgeLighting.response(to: point, around: bubble, reach: 80)
        let airPodsLighting = model.hidden || model.leadingAirPods == nil ? EdgeLighting()
            : EdgeLighting.response(to: point, around: airPodsSatelliteRect, reach: 80)
        let pillY = body.maxY - (model.collapsedHeight + NotchModel.volumePillHeight) / 2
        let pillX = body.maxX + NotchModel.volumePillGap
        let chargeRect = NSRect(x: pillX, y: pillY, width: NotchModel.chargePillWidth, height: NotchModel.volumePillHeight)
        let chargeLighting = model.hidden || model.trailingCharge == nil ? EdgeLighting()
            : EdgeLighting.response(to: point, around: chargeRect, reach: 80)
        let pillRect = NSRect(x: pillX + model.volumePillExtraOffset, y: pillY,
                              width: NotchModel.volumePillWidth, height: NotchModel.volumePillHeight)
        let pillLighting = model.hidden || model.trailingVolume == nil ? EdgeLighting()
            : EdgeLighting.response(to: point, around: pillRect, reach: 80)
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
        model.onSurfaceChanged = nil
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panel.orderOut(nil)
    }
}
