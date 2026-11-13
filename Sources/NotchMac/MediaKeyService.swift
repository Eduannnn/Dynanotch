import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import NotchCore

/// A hardware/session event filter prevents the system HUD trigger. It never stops OSDUIHelper/ControlCenter.
/// Its main-thread filter passes normal typing through. Only Cmd-comma over the notch is consumed.
@MainActor final class MediaKeyService: ObservableObject {
    enum Status { case off, needsAccessibility, unavailable, active }
    @Published private(set) var status: Status = .off
    private(set) var tapLocation = "none"
    var perform: ((HardwareMediaKey, Bool) -> Bool)?
    var settingsShortcut: (() -> Bool)?
    private var capturedSettingsKey: Int64?
    private var requested = true
    private var started = false
    private var suspended = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var capture = MediaKeyCapture()

    var message: String {
        switch status {
        case .off: "macOS handles the hardware keys."
        case .needsAccessibility: "Allow Accessibility access to replace the macOS volume and brightness HUD."
        case .unavailable: "macOS could not enable key takeover. The hardware keys still work normally."
        case .active: "The notch handles volume and brightness keys. The macOS HUD is suppressed for handled keys."
        }
    }

    func configure(enabled: Bool) {
        requested = enabled
        guard started else { return }
        refresh()
    }
    func suspendForLockScreen(_ suspended: Bool) {
        guard self.suspended != suspended else { return }
        self.suspended = suspended
        if started { refresh() }
    }

    func start() {
        guard !started else { return }
        started = true; refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 0.4
    }
    func stop() {
        timer?.invalidate(); timer = nil; started = false
        tearDownTap(); setStatus(.off)
    }

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
        refresh()
    }

    private func refresh() {
        guard !suspended, requested || settingsShortcut != nil else { tearDownTap(); setStatus(.off); return }
        guard AXIsProcessTrusted() else { tearDownTap(); setStatus(requested ? .needsAccessibility : .off); return }
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            setStatus(requested ? (CGEvent.tapIsEnabled(tap: tap) ? .active : .unavailable) : .off)
            return
        }
        let mask = (CGEventMask(1) << 14) | (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<MediaKeyService>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated { service.filter(type: type, event: event) }
        }
        // Use the earliest authorized filter. Some OS/security configurations only allow the session location.
        let hardware = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: context)
        let port = hardware ?? CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: context)
        guard let port else { setStatus(.unavailable); return }
        tapLocation = hardware != nil ? "hardware" : "session"
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else { CFMachPortInvalidate(port); setStatus(.unavailable); return }
        tap = port; source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        setStatus(requested ? (CGEvent.tapIsEnabled(tap: port) ? .active : .unavailable) : .off)
    }

    private func filter(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            capture.reset()
            capturedSettingsKey = nil
            if started, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyUp, event.getIntegerValueField(.keyboardEventKeycode) == capturedSettingsKey {
            capturedSettingsKey = nil; return nil
        }
        if type == .keyDown, let cocoa = NSEvent(cgEvent: event) {
            let flags = cocoa.modifierFlags
            if isNotchSettingsShortcut(characters: cocoa.charactersIgnoringModifiers, command: flags.contains(.command),
                shift: flags.contains(.shift), option: flags.contains(.option), control: flags.contains(.control), overNotch: true),
                settingsShortcut?() == true {
                capturedSettingsKey = event.getIntegerValueField(.keyboardEventKeycode); return nil
            }
            return Unmanaged.passUnretained(event)
        }
        guard requested, type.rawValue == 14, let cocoa = NSEvent(cgEvent: event),
              let stroke = HardwareMediaKeyStroke.decode(subtype: cocoa.subtype.rawValue, data1: cocoa.data1) else { return Unmanaged.passUnretained(event) }
        let flags = cocoa.modifierFlags
        // Preserve Option shortcuts to System Settings and Command/Control combinations.
        let eligible = !flags.contains(.command) && !flags.contains(.control) && (!flags.contains(.option) || flags.contains(.shift))
        let fine = flags.contains(.option) && flags.contains(.shift)
        let action = perform
        let consumed = capture.route(stroke, eligible: eligible) { key in action?(key, fine) ?? false }
        return consumed ? nil : Unmanaged.passUnretained(event)
    }
    private func tearDownTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil; tapLocation = "none"; capture.reset(); capturedSettingsKey = nil
    }
    private func setStatus(_ next: Status) { if status != next { status = next } }
}
