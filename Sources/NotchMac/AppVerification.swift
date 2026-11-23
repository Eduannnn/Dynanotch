import AppKit
import SwiftUI
import NotchCore

/// Runs the real models and renderer with isolated preferences and no device/media side effects.
@MainActor enum AppVerification {
    static func runNotchless(directory: String) {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        let store = NotchThemeStore(folder: output.appendingPathComponent(UUID().uuidString), watch: false)
        let file = store.folder.appendingPathComponent("notchless.json")
        try? JSONSerialization.data(withJSONObject: ["layout": ["idlePillSeconds": 0.2, "idleShrinkSeconds": 0.2]]).write(to: file)
        store.reload()
        let defaults = UserDefaults(suiteName: "DynanotchNotchlessTest." + UUID().uuidString)!
        let model = NotchModel(preferences: Preferences(defaults: defaults), themes: store)
        model.media.stop(); model.hasHardwareNotch = false; model.cameraWidth = 18; model.cameraHeight = 28
        model.availableWidth = 1280
        model.updateIdlePill()
        render(model, output.appendingPathComponent("idle-pill.png"))
        var checks = ["startsAsPill": model.surfaceTarget.width == 64,
                      "smallerUI": model.notchScale == 0.85,
                      "floatingOutline": model.surfaceTarget.ear == 0]
        DispatchQueue.main.asyncAfter(deadline: .now()+0.3) {
            checks["shrinksWithoutIntermediateStop"] = model.idlePillPhase == .shrinking && model.surfaceTarget.width == 0.1
            render(model, output.appendingPathComponent("idle-shrinking.png"))
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+0.6) {
            checks["eventuallyHides"] = model.idlePillPhase == .hidden
            model.media.setPreview(true); model.updateIdlePill()
            checks["activityRestoresPill"] = model.presentation == .collapsed && model.idlePillPhase == .pill
            render(model, output.appendingPathComponent("compact-player.png"))
            model.toggleExpansion()
            checks["playerOpens"] = model.presentation == .expanded && model.surfaceTarget.ear == 0
            render(model, output.appendingPathComponent("expanded-player.png"), width: 800)
            model.previewCharging(); model.previewNotice()
            render(model, output.appendingPathComponent("simultaneous-activities.png"), width: 800)
            model.media.setPreview(false)
            model.stop()
            var report: [String: Any] = checks
            report["result"] = checks.values.allSatisfy { $0 } ? "pass" : "fail"
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]) {
                try? data.write(to: output.appendingPathComponent("result.json"))
            }
            NSApp.terminate(nil)
        }
    }

    static func runThemes(directory: String) {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        let folder = output.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = NotchThemeStore(folder: folder)
        let defaults = UserDefaults(suiteName: "DynanotchThemeTest." + UUID().uuidString)!
        let model = NotchModel(preferences: Preferences(defaults: defaults), themes: store)
        model.media.stop(); model.media.setPreview(true); model.pinned = true; model.hovering = true
        model.cameraWidth = 208; model.cameraHeight = 37.5; model.availableWidth = 1710
        func save(_ value: [String: Any], _ name: String) {
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]) {
                try? data.write(to: folder.appendingPathComponent(name + ".json"), options: .atomic)
            }
        }
        var checks: [String: Bool] = [:]
        checks["defaultsLoad"] = store.error.isEmpty && store.theme(state: "expanded").number("surface.width", 360) == 360
        let baseline = model.surfaceTarget
        model.preferences.liquidGlass = true
        checks["glassUsesSameGeometry"] = model.surfaceTarget == baseline
        model.preferences.liquidGlass = false
        checks["defaultDesignMeasurements"] = baseline.radius == 30 && model.design.headerPadding == 18
            && model.design.controlsPadding == 24 && model.design.satelliteSpacing == 8
        save(["design": ["basePadding": 10, "expandedRadius": 36, "controlSpacing": 9, "satelliteSpacing": 12],
              "layers": [["surfaceInset": 6, "color": "#14FFFFFF", "opacity": 0.3]]], "global")
        store.reload()
        checks["designTokensApply"] = model.surfaceTarget.radius == 36 && model.design.headerPadding == 15
            && model.design.controlsPadding == 20 && model.design.controlSpacing == 9 && model.bubbleGap == 12
        checks["concentricInsets"] = NotchDesign.concentricRadius(outer: 36, padding: 6) == 30
            && NotchDesign.concentricRadius(outer: 4, padding: 6) == 0
        render(model, output.appendingPathComponent("concentric-layer.png"))
        save(["design": ["basePadding": -2]], "global"); store.reload()
        checks["invalidDesignRetainsLastGood"] = !store.error.isEmpty && model.design.headerPadding == 15
        save(["layout": ["headerPadding": 19, "bubbleGap": 60]], "global"); store.reload()
        checks["legacyLayoutStillApplies"] = model.design.headerPadding == 19 && model.bubbleGap == 60
        save([:], "global"); store.reload()
        save(["version": 1, "surface": ["width": 480, "height": 240, "radius": 42],
              "elements": ["title": ["color": "#FFAA00", "offsetX": 7]]], "expanded")
        store.reload()
        checks["geometryAndElementsApply"] = model.bodyWidth == 480 && model.contentHeight == 240
            && model.surfaceTarget.radius == 42 && model.theme.element("title").number("offsetX", 0) == 7
        render(model, output.appendingPathComponent("custom-expanded.png"), width: 800)
        save(["surface": ["width": 510]], "locked"); store.reload()
        checks["lockedInheritance"] = store.theme(state: "expanded", locked: true).number("surface.width", 0) == 510
            && store.theme(state: "expanded", locked: true).number("surface.radius", 0) == 42
        try? Data("{ broken".utf8).write(to: folder.appendingPathComponent("expanded.json"))
        store.reload()
        checks["invalidJSONRetainsLastGood"] = !store.error.isEmpty && model.bodyWidth == 480
        save(["surface": ["width": "wrong type"]], "expanded"); store.reload()
        checks["invalidTypeRetainsLastGood"] = !store.error.isEmpty && model.bodyWidth == 480
        save(["surface": ["width": 490]], "expanded"); store.reload()
        checks["recoversAfterCorrection"] = store.error.isEmpty && model.bodyWidth == 490
        save(["surface": ["width": 500]], "expanded")
        DispatchQueue.main.asyncAfter(deadline: .now()+1) {
            checks["fileWatcherReloads"] = store.error.isEmpty && model.bodyWidth == 500
            let pass = checks.values.allSatisfy { $0 }
            var report: [String: Any] = checks
            report["result"] = pass ? "pass" : "fail"
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output.appendingPathComponent("result.json")); print(String(decoding: data, as: UTF8.self))
            }
            model.stop()
            NSApp.terminate(nil)
        }
    }

    static func runNativeSkips(directory: String) {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 140), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Dynanotch · Apple skip-animation check"
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
        content.wantsLayer = true; content.layer?.backgroundColor = NSColor.black.cgColor
        let previous = NativeSkipGlyphHost(frame: NSRect(x: 84, y: 65, width: 39, height: 22))
        let next = NativeSkipGlyphHost(frame: NSRect(x: 0, y: 0, width: 39, height: 22))
        next.setFrameOrigin(NSPoint(x: 237, y: 65))
        previous.update(backwards: true, trigger: 0, reduceMotion: false)
        next.update(backwards: false, trigger: 0, reduceMotion: false)
        content.addSubview(previous); content.addSubview(next)
        for (title, x) in [("Previous", 75.0), ("Next", 241.0)] {
            let label = NSTextField(labelWithString: title)
            label.textColor = .secondaryLabelColor; label.frame = NSRect(x: x, y: 28, width: 70, height: 18)
            content.addSubview(label)
        }
        window.contentView = content; window.center(); window.makeKeyAndOrderFront(nil)
        let ready: [String: Any] = ["windowID": window.windowNumber, "readyTime": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: ready) { try? data.write(to: output.appendingPathComponent("ready.json")) }
        var history: [String] = []
        var animationObserved = false
        var eachTapAnimates = true
        var eachTapTravels = true
        let initialStatePrimed = previous.stateName == "State 1" && next.stateName == "State 1"
            && previous.activeNativeAnimationCount == 0 && next.activeNativeAnimationCount == 0
        func hasAnimation(_ layer: CALayer?) -> Bool {
            guard let layer else { return false }
            return !(layer.animationKeys() ?? []).isEmpty || (layer.sublayers ?? []).contains { hasAnimation($0) }
        }
        for (offset, delay) in [0.75, 0.85, 1.9, 3.0, 4.1].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                previous.update(backwards: true, trigger: offset + 1, reduceMotion: false)
                next.update(backwards: false, trigger: offset + 1, reduceMotion: false)
                history.append(next.stateName)
                animationObserved = animationObserved || hasAnimation(next.layer)
                eachTapAnimates = eachTapAnimates && previous.activeNativeAnimationCount > 0 && next.activeNativeAnimationCount > 0
                eachTapTravels = eachTapTravels && previous.lastVisibleArrowTravel > 20 && next.lastVisibleArrowTravel > 20
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.25) {
            let state = next.stateName
            next.update(backwards: false, trigger: 6, reduceMotion: true)
            let reducedMotion = next.stateName == state
            let loaded = previous.loadedNativeAnimation && next.loadedNativeAnimation
            let remounted = NativeSkipGlyphHost(frame: .zero)
            remounted.update(backwards: false, trigger: 42, reduceMotion: false)
            let remountDoesNotReplay = remounted.stateName == "State 1" && remounted.activeNativeAnimationCount == 0
            remounted.update(backwards: false, trigger: 43, reduceMotion: false)
            let remountFirstTapWorks = remounted.stateName == "State 2" && remounted.lastVisibleArrowTravel > 20
            let passed = loaded && animationObserved && reducedMotion && initialStatePrimed && eachTapAnimates && eachTapTravels
                && remountDoesNotReplay && remountFirstTapWorks && history == ["State 2", "State 3", "State 4", "State 1", "State 2"]
            let result: [String: Any] = ["result": passed ? "pass" : "fail", "nativeLoaded": loaded,
                "animationObserved": animationObserved, "tapStates": history, "reducedMotionHeldState": reducedMotion,
                "initialStatePrimed": initialStatePrimed, "eachTapAnimates": eachTapAnimates, "eachTapTravels": eachTapTravels,
                "remountDoesNotReplay": remountDoesNotReplay, "remountFirstTapWorks": remountFirstTapWorks,
                "source": "/System/Library/PrivateFrameworks/NowPlayingUI.framework/Resources/ForwardBackward.caar",
                "scope": "Original installed Apple vector resource in our hardened app process; rapid taps and state wrap; no media commands or Apple process modifications."]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output.appendingPathComponent("result.json")); print(String(decoding: data, as: UTF8.self))
            }
            window.orderOut(nil); NSApp.terminate(nil)
        }
    }
    static func runVisual(directory: String) {
        if CommandLine.arguments.contains("--inline-airpods") { runInlineAirPods(directory: directory); return }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "com.eduannnn.dynanotch.visual-check." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let model = NotchModel(preferences: Preferences(defaults: defaults))
        model.preferences.liquidGlass = CommandLine.arguments.contains("--liquid-glass")
        model.cameraWidth = 208; model.cameraHeight = 37.5; model.availableWidth = 1710
        model.displayScreen = NSScreen.main
        model.media.setPreview(true); model.pinned = true; model.hovering = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Dynanotch · cover-turn visual check"
        window.contentView = NSHostingView(rootView: NotchRootView(model: model)
            .frame(width: 540, height: 280, alignment: .top).clipped()
            .background {
                if model.preferences.liquidGlass,
                   let image = NSImage(contentsOfFile: "/System/Library/CoreServices/DefaultDesktop.heic") {
                    Image(nsImage: image).resizable().scaledToFill()
                } else { Color(red: 0.13, green: 0.16, blue: 0.2) }
            })
        window.level = .floating
        window.center(); window.makeKeyAndOrderFront(nil)
        let frame = window.frame
        let rect = "\(Int(frame.minX)),\(Int(NSScreen.main!.frame.maxY-frame.maxY)),\(Int(frame.width)),\(Int(frame.height))"
        try? rect.write(to: output.appendingPathComponent("capture-rect.txt"), atomically: true, encoding: .utf8)
        let ready: [String: Any] = ["windowID": window.windowNumber, "readyTime": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: ready) { try? data.write(to: output.appendingPathComponent("ready.json")) }
        if CommandLine.arguments.contains("--glass-motion") {
            var heights: [CGFloat] = []
            model.onSurfaceChanged = { [weak model] in
                if let height = model?.presentedSurface?.height { heights.append(height) }
            }
            for (time, open) in [(0.25, false), (0.38, true), (0.52, false), (0.65, true),
                                 (0.9, false), (1.05, true), (1.5, false), (2.1, true)] {
                DispatchQueue.main.asyncAfter(deadline: .now()+time) {
                    if open { model.toggleExpansion() } else { model.close() }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now()+3.5) {
                let deltas = zip(heights, heights.dropFirst()).map { abs($1-$0) }
                let settled = abs((model.presentedSurface?.height ?? 0) - model.surfaceTarget.height) < 1
                let pass = NotchClearGlassView.isSupported && heights.count > 10 && settled
                    && heights.allSatisfy { $0.isFinite && $0 > 0 }
                let report: [String: Any] = ["result": pass ? "pass" : "fail", "frames": heights.count,
                    "maxFrameHeightChange": deltas.max() ?? 0, "settled": settled,
                    "nativeRefractionAvailable": NotchClearGlassView.isSupported,
                    "scope": "Live renderer; eight interrupted opening/collapse transitions; isolated preview playback."]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]) {
                    try? data.write(to: output.appendingPathComponent("result.json"))
                }
                model.onSurfaceChanged = nil
                model.stop(); window.orderOut(nil); defaults.removePersistentDomain(forName: suite)
                NSApp.terminate(nil)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+1) { model.media.command("next track") }
        DispatchQueue.main.asyncAfter(deadline: .now()+1.05) { model.media.command("next track") }
        DispatchQueue.main.asyncAfter(deadline: .now()+1.85) { model.media.command("playpause") }
        DispatchQueue.main.asyncAfter(deadline: .now()+2.15) { model.media.command("playpause") }
        DispatchQueue.main.asyncAfter(deadline: .now()+2.6) {
            let passed = model.artworkTurns > 0 && model.artworkTurnPhase == "idle" && model.media.snapshot?.identity.identifier == "preview-2"
            let result: [String: Any] = ["result": passed ? "pass" : "fail", "artworkTurns": model.artworkTurns,
                "phase": model.artworkTurnPhase, "latestTrack": model.media.snapshot?.identity.identifier ?? "none",
                "scope": "Actual SwiftUI cover turnover with two rapid preview-track changes; actual playback untouched."]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output.appendingPathComponent("result.json")); print(String(decoding: data, as: UTF8.self))
            }
            window.orderOut(nil); model.stop(); defaults.removePersistentDomain(forName: suite)
            NSApp.terminate(nil)
        }
    }
    static func runInlineAirPods(directory: String) {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "com.eduannnn.dynanotch.inline-check." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let model = NotchModel(preferences: Preferences(defaults: defaults))
        model.media.stop()
        model.cameraWidth = 208; model.cameraHeight = 37.5; model.availableWidth = 1710
        model.displayScreen = NSScreen.main
        model.preferences.liquidGlass = CommandLine.arguments.contains("--liquid-glass")
        model.previewNotice(artwork: .init(family: .airpodsPro), battery: 0.43)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 150),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Dynanotch · AirPods horizontal expansion"
        window.level = .floating
        window.contentView = NSHostingView(rootView: NotchRootView(model: model)
            .frame(width: 920, height: 150, alignment: .top).clipped()
            .background(Color(red: 0.13, green: 0.16, blue: 0.2)))
        window.center(); window.makeKeyAndOrderFront(nil)
        let frame = window.frame
        let rect = "\(Int(frame.minX)),\(Int(NSScreen.main!.frame.maxY-frame.maxY)),\(Int(frame.width)),\(Int(frame.height))"
        try? rect.write(to: output.appendingPathComponent("capture-rect.txt"), atomically: true, encoding: .utf8)
        DispatchQueue.main.asyncAfter(deadline: .now()+0.5) {
            if let notice = model.inlineAirPods { model.toggleAirPodsDetails(notice.id) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+9) {
            let pass = model.showsInlineAirPodsDetails && model.contentHeight == model.collapsedHeight
                && model.inlineAirPods.map { model.shouldPlayAirPodsMovie($0.id) } == true
            let report: [String: Any] = ["result": pass ? "pass" : "fail", "horizontalDetails": pass,
                                       "moviePlaybackRequestedAfterFullRotation": pass]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]) {
                try? data.write(to: output.appendingPathComponent("result.json"))
            }
            model.stop(); window.orderOut(nil); defaults.removePersistentDomain(forName: suite)
            NSApp.terminate(nil)
        }
    }

    static func runStress(directory: String) {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "com.eduannnn.dynanotch.stress." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let model = NotchModel(preferences: Preferences(defaults: defaults))
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }
        model.cameraWidth = 208; model.cameraHeight = 37.5; model.availableWidth = screen.frame.width
        model.displayScreen = screen
        model.media.stop() // Clearing preview playback must never poll a real player.
        let size = CGSize(width: 640, height: 205)
        let rect = CGRect(x: floor(screen.frame.midX - size.width / 2), y: floor(screen.frame.maxY - size.height - 75),
                          width: size.width, height: size.height)
        let window = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .floating
        window.ignoresMouseEvents = true
        window.contentView = NSHostingView(rootView: NotchRootView(model: model)
            .frame(width: size.width, height: size.height, alignment: .top).clipped()
            .background(Color(red: 0.13, green: 0.16, blue: 0.2)))
        window.orderFrontRegardless()
        let captureRect = "\(Int(rect.minX)),\(Int(screen.frame.maxY - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))"
        try? captureRect.write(to: output.appendingPathComponent("capture-rect.txt"), atomically: true, encoding: .utf8)

        var report: [[String: String]] = []
        func step(_ time: Double, _ name: String, _ action: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + time + 2) {
                action()
                report.append(["time": String(time + 2), "scenario": name, "presentation": model.presentation.rawValue])
            }
        }
        step(0, "Idle") {}
        step(0.5, "Standalone charging at 57%") { model.previewCharging(battery: 0.57) }
        step(3, "Collapsed music") { model.media.setPreview(true) }
        step(3.8, "Expanded music") { model.toggleExpansion() }
        step(4.4, "Next track") { model.media.command("next track") }
        step(4.6, "Previous track during flip") { model.media.command("previous track") }
        step(5.5, "Expanded low volume") { model.showOSD(.init(kind: .volume, level: 0.025, muted: false)) }
        step(6.2, "Collapsed mute") { model.close(); model.showOSD(.init(kind: .volume, level: 0, muted: true)) }
        step(7, "Paused music and brightness") {
            model.media.command("playpause")
            model.showOSD(.init(kind: .brightness, level: 0.08, muted: false))
        }
        step(9, "Player exits while collapsed") { model.media.setPreview(false) }
        step(10, "Music returns and charging starts") { model.media.setPreview(true); model.previewCharging(battery: 0.57) }
        step(11.4, "AirPods joins charging") { model.previewNotice() }
        step(11.9, "Volume with two device satellites") { model.showOSD(.init(kind: .volume, level: 0.18, muted: false)) }
        step(12.3, "Lock during simultaneous activities") { model.updateScreenLock(true, animateUnlock: false) }
        step(13, "Unlock and merge music back") { model.updateScreenLock(false, animateUnlock: true) }
        step(15, "Media exits") { model.media.setPreview(false) }
        step(15.7, "Inline AirPods") { model.previewNotice() }
        step(16.3, "Expanded inline AirPods details") {
            if let notice = model.inlineAirPods { model.toggleAirPodsDetails(notice.id) }
        }
        step(17.8, "Collapse then show AirPods Max") {
            model.closeAirPodsDetails()
            model.previewNotice(artwork: .init(family: .airpodsMax), battery: 0.62)
            if let notice = model.inlineAirPods { model.toggleAirPodsDetails(notice.id) }
        }
        step(19.3, "Missing AirPods readings") {
            model.closeAirPodsDetails()
            model.previewNotice(battery: nil)
            if let notice = model.inlineAirPods { model.toggleAirPodsDetails(notice.id) }
        }
        step(20.8, "Disconnect while expanded") {
            if let notice = model.inlineAirPods {
                model.enqueue(.init(key: notice.key, name: notice.name, kind: notice.kind,
                                    connected: false, airPodsArtwork: notice.airPodsArtwork))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 26) {
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output.appendingPathComponent("timeline.json"))
            }
            window.orderOut(nil); model.stop(); defaults.removePersistentDomain(forName: suite)
            NSApp.terminate(nil)
        }
    }

    static func run(directory: String) {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "com.eduannnn.dynanotch.verification." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let model = NotchModel(preferences: Preferences(defaults: defaults))
        model.cameraWidth = 208; model.cameraHeight = 37.5; model.availableWidth = 1710
        model.media.setPreview(true); model.peek = false; model.hovering = true; model.pinned = true
        render(model, output.appendingPathComponent("music-expanded.png"))
        model.close()
        model.media.command("next track")
        let trackChangeStaysCollapsed = model.presentation == .collapsed && !model.peek
        let nextFlipsForward = !model.media.artworkFlipsBackward
        model.media.command("previous track")
        let previousFlipsBackward = model.media.artworkFlipsBackward
        model.media.command("next track")
        let compact = model.surfaceTarget
        render(model, output.appendingPathComponent("music-compact.png"))
        model.osd = .init(kind: .volume, level: 0.6, muted: false)
        func osdTakesOver(_ model: NotchModel) -> Bool {
            model.presentation == .osd && !model.showsMediaBubble && !model.showsLockBubble
                && model.contentHeight > model.cameraHeight && model.bodyOffset == 0
        }
        let volumeReplacesMusic = osdTakesOver(model)
        render(model, output.appendingPathComponent("music-volume-compact.png"))
        model.pinned = true; model.hovering = true
        let volumeReplacesExpanded = osdTakesOver(model)
        model.osd = .init(kind: .brightness, level: 0.4, muted: false)
        let brightnessReplacesExpanded = osdTakesOver(model)
        model.media.command("playpause")
        let pausedPlayerUsesBrightnessOSD = osdTakesOver(model)
        model.osd = nil
        let osdRestoresExpanded = model.presentation == .expanded && model.pinned
        model.media.command("playpause")
        model.media.command("playpause")
        model.close(); model.previewNotice()
        let noticeDisplacesMedia = model.presentation == .notice && model.showsMediaBubble
            && model.surfaceTarget.artworkX < 0
        render(model, output.appendingPathComponent("notice-with-media-bubble.png"))
        let inlineHeight = model.contentHeight
        let inlineWidth = model.bodyWidth
        let inlineLeft = -model.bodyWidth / 2 + model.bodyOffset
        if let notice = model.inlineAirPods { model.toggleAirPodsDetails(notice.id) }
        let inlineAirPodsExpanded = model.showsInlineAirPodsDetails && model.contentHeight == inlineHeight
            && model.bodyWidth > inlineWidth && abs(-model.bodyWidth / 2 + model.bodyOffset - inlineLeft) < 0.001
        render(model, output.appendingPathComponent("inline-airpods-battery-details.png"), width: 800)
        model.closeAirPodsDetails()
        let inlineAirPodsCollapsed = !model.showsInlineAirPodsDetails && model.contentHeight == inlineHeight
        model.osd = .init(kind: .volume, level: 0.6, muted: false)
        let volumeReplacesNotice = osdTakesOver(model) && model.mainNotice?.airPodsArtwork != nil
        model.osd = nil
        model.activateBubble()
        let bubbleRestoresMedia = model.presentation == .expanded && !model.showsMediaBubble
        let chargingLayout = NotchModel(preferences: Preferences(defaults: defaults))
        chargingLayout.cameraWidth = 208; chargingLayout.cameraHeight = 37.5; chargingLayout.availableWidth = 1710
        chargingLayout.media.setPreview(true)
        chargingLayout.toggleExpansion()
        chargingLayout.previewNotice()
        chargingLayout.previewCharging()
        func chargingTakesOver(_ model: NotchModel) -> Bool {
            model.presentation == .notice && model.mainNotice?.kind == .charging
                && !model.showsMediaBubble && !model.showsLockBubble && model.leadingAirPods == nil
                && model.lockScreenNotice == nil
        }
        let chargingTakesCenter = chargingTakesOver(chargingLayout)
        render(chargingLayout, output.appendingPathComponent("charging-takeover.png"))
        chargingLayout.screenLocked = true
        let lockedChargingTakesCenter = chargingTakesOver(chargingLayout)
        render(chargingLayout, output.appendingPathComponent("locked-charging-takeover.png"))
        var chargingRestoresPlayer = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.25) {
            chargingRestoresPlayer = chargingLayout.chargingTakeover == nil
                && chargingLayout.presentation == .expanded && chargingLayout.showsLockBubble
                && chargingLayout.leadingAirPods != nil
        }
        model.media.command("playpause")
        let musicLayout = NotchModel(preferences: Preferences(defaults: defaults))
        musicLayout.cameraWidth = 208; musicLayout.cameraHeight = 37.5; musicLayout.availableWidth = 1710
        musicLayout.media.setPreview(true)
        musicLayout.previewNotice(battery: nil)
        let musicKeepsCenter = musicLayout.presentation == .collapsed && !musicLayout.showsMediaBubble
            && musicLayout.leadingAirPods?.airPodsArtwork != nil && musicLayout.leadingAirPods?.battery == nil
        render(musicLayout, output.appendingPathComponent("music-with-airpods.png"))
        musicLayout.previewNotice(battery: 0.75)
        render(musicLayout, output.appendingPathComponent("airpods-connected-with-music.png"))
        musicLayout.osd = .init(kind: .volume, level: 0.6, muted: false)
        let volumeReplacesMusicWithNotices = osdTakesOver(musicLayout)
            && musicLayout.leadingAirPods != nil
        render(musicLayout, output.appendingPathComponent("compact-volume-with-airpods.png"))
        musicLayout.screenLocked = true
        let lockedVolumeVisible = osdTakesOver(musicLayout)
            && musicLayout.leadingAirPods != nil
        musicLayout.osd = .init(kind: .brightness, level: 0.4375, muted: false)
        let lockedBrightnessVisible = osdTakesOver(musicLayout)
        render(musicLayout, output.appendingPathComponent("locked-brightness.png"))
        musicLayout.osd = nil
        let lockedBubblesActivities = musicLayout.presentation == .collapsed && !musicLayout.showsMediaBubble && musicLayout.showsLockBubble
            && musicLayout.leadingAirPods != nil
        render(musicLayout, output.appendingPathComponent("locked-with-music-airpods.png"))
        musicLayout.toggleExpansion()
        let lockedPlayerOpens = musicLayout.presentation == .expanded && musicLayout.showsLockBubble
            && !musicLayout.showsMediaBubble
        render(musicLayout, output.appendingPathComponent("locked-expanded-player-with-lock-bubble.png"))
        musicLayout.toggleExpansion()
        let lockedPlayerCloses = musicLayout.presentation == .collapsed && musicLayout.showsLockBubble
        musicLayout.screenLocked = false
        musicLayout.osd = nil
        let nativeCombinedWins = AirPodsBatteryDetails(left: 0.68, right: 0.43,
                                                       chargingCase: 0.92, combined: 0.45).listeningLevel == 0.45
        let missingCombinedUsesEarbuds = AirPodsBatteryDetails(left: 0.68, right: 0.43,
                                                               chargingCase: 0.12).listeningLevel == 0.43
        let unavailableChargeStaysUnknown = AirPodsBatteryDetails(chargingCase: 0.92).listeningLevel == nil
        let musicKeepsBatteryReading = musicLayout.leadingAirPods?.battery == 0.43
            && musicLayout.previewAirPodsBatteryDetails == .init(left: 0.68, right: 0.43, chargingCase: 0.92)
        if let id = musicLayout.leadingAirPods?.id {
            musicLayout.holdAirPodsNotice(id, open: true)
            render(musicLayout, output.appendingPathComponent("airpods-expanded-battery.png"), width: 800)
            musicLayout.holdAirPodsNotice(id, open: false)
        }
        let inlineLayout = NotchModel(preferences: Preferences(defaults: defaults))
        inlineLayout.previewNotice()
        let playbackWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 140),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        playbackWindow.isReleasedWhenClosed = false
        playbackWindow.ignoresMouseEvents = true
        playbackWindow.alphaValue = 0.02
        playbackWindow.contentView = NSHostingView(rootView: VStack(spacing: 0) {
            NotchRootView(model: musicLayout).frame(width: 540, height: 70, alignment: .top).clipped()
            NotchRootView(model: inlineLayout).frame(width: 540, height: 70, alignment: .top).clipped()
        })
        playbackWindow.orderFrontRegardless()
        let expectsMovie = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && SystemAirPodsArtwork.url(for: .airpodsPro) != nil
        var survivesOldCutoff = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            survivesOldCutoff = !expectsMovie || (musicLayout.leadingAirPods != nil && inlineLayout.mainNotice != nil)
        }
        let morphModel = NotchModel(preferences: Preferences(defaults: defaults))
        morphModel.cameraWidth = 208; morphModel.cameraHeight = 37.5; morphModel.availableWidth = 1710
        morphModel.media.setPreview(true)
        let testArtwork = AirPodsArtwork(family: .airpodsPro)
        let testNotice = DeviceNotice(key: "fixture/airpods", name: "AirPods Pro", kind: .earbuds,
                                      battery: 0.63, airPodsArtwork: testArtwork)
        morphModel.system.loadRenderingPreview(devices: [
            .init(id: testNotice.key, name: testNotice.name, connected: true, kind: .earbuds,
                  airPodsArtwork: testArtwork, airPodsBattery: .init(left: 0.63, right: 0.71, chargingCase: 0.89))
        ])
        morphModel.enqueue(testNotice)
        let centerBeforeMorph = morphModel.surfaceTarget
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 80),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0.02
        window.contentView = NSHostingView(rootView: NotchRootView(model: morphModel)
            .frame(width: 800, height: 80, alignment: .top).clipped())
        window.orderFrontRegardless()
        var sawIntermediateWidth = false
        var compactSatelliteFrame: CGRect?
        var reopened = false
        var collapsedAgain = false
        var disconnected = false
        let reducingMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            compactSatelliteFrame = morphModel.presentedSatellites[.airPods]
            morphModel.toggleAirPodsDetails(testNotice.id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.29) {
            let width = morphModel.airPodsSatelliteWidth
            sawIntermediateWidth = reducingMotion || (width > NotchModel.airPodsPillSize && width < NotchModel.airPodsExpandedWidth)
            morphModel.toggleAirPodsDetails(testNotice.id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.37) { morphModel.toggleAirPodsDetails(testNotice.id) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.10) {
            if let frame = morphModel.presentedSatellites[.airPods] {
                let expectedRight = (NotchRootView.canvasWidth - centerBeforeMorph.width) / 2
                    + centerBeforeMorph.offset - NotchModel.volumePillGap
                reopened = abs(frame.width - NotchModel.airPodsExpandedWidth) < 1
                    && abs(frame.maxX - expectedRight) < 1
                    && (compactSatelliteFrame?.minX ?? 0) > frame.minX
                    && morphModel.surfaceTarget == centerBeforeMorph
            }
            render(morphModel, output.appendingPathComponent("airpods-horizontal-levels.png"), width: 800)
            morphModel.toggleAirPodsDetails(testNotice.id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.75) {
            collapsedAgain = abs(morphModel.airPodsSatelliteWidth - NotchModel.airPodsPillSize) < 1
            morphModel.toggleAirPodsDetails(testNotice.id)
            morphModel.enqueue(.init(key: testNotice.key, name: testNotice.name, kind: .earbuds,
                                      connected: false, airPodsArtwork: testArtwork))
            disconnected = morphModel.heldAirPodsNotice == nil && morphModel.leadingAirPods == nil
        }
        let maxLayout = NotchModel(preferences: Preferences(defaults: defaults))
        maxLayout.cameraWidth = 208; maxLayout.cameraHeight = 37.5; maxLayout.availableWidth = 1710
        maxLayout.media.setPreview(true)
        maxLayout.previewNotice(artwork: .init(family: .airpodsMax), battery: 0.62)
        if let id = maxLayout.leadingAirPods?.id {
            maxLayout.holdAirPodsNotice(id, open: true)
            render(maxLayout, output.appendingPathComponent("airpods-max-horizontal.png"), width: 800)
        }
        maxLayout.stop()
        let staggered = NotchModel(preferences: Preferences(defaults: defaults))
        staggered.enqueue(.init(key: "intervening-usb", name: "USB Device", kind: .usb))
        staggered.previewCharging()
        let chargingInterruptsNotice = chargingTakesOver(staggered) && staggered.notices.current?.kind == .usb
        var chargingRestoresNotice = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            chargingRestoresNotice = staggered.presentation == .notice && staggered.mainNotice?.kind == .usb
        }
        model.close()
        model.screenLocked = true
        let lockedCollapses = model.presentation == .collapsed && !model.showsMediaBubble && model.showsLockBubble
            && model.contentHeight == model.collapsedHeight
            && model.bodyWidth == model.cameraWidth + model.compactLeadingWidth + model.compactTrailingWidth
            && model.bodyOffset == 0
        model.toggleExpansion()
        let lockedPlayerExpands = model.presentation == .expanded && model.showsLockBubble && !model.showsMediaBubble
        model.updateScreenLock(false, animateUnlock: true)
        let unlockKeepsPlayerAndLockBubble = !model.screenLocked && model.isUnlocking
            && model.presentation == .expanded && model.showsLockBubble && !model.showsMediaBubble
        render(model, output.appendingPathComponent("unlock-padlock-open.png"))
        var unlockRestoresExpansion = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            unlockRestoresExpansion = !model.isUnlocking && model.presentation == .expanded
        }
        let motion = NotchAnimationCoordinator()
        let lockMotion = NotchAnimationCoordinator()
        let expanded = NotchSurface(width: 400, height: 193.5, offset: 0, radius: 30, ear: 12)
        lockMotion.update(compact, screen: NSScreen.main, immediate: true)
        lockMotion.update(expanded, screen: NSScreen.main, useRunLoopTimer: true)
        motion.update(compact, screen: NSScreen.main, immediate: true)
        motion.update(expanded, screen: NSScreen.main)
        DispatchQueue.main.asyncAfter(deadline: .now()+0.08) { motion.update(compact, screen: NSScreen.main) }
        DispatchQueue.main.asyncAfter(deadline: .now()+0.16) { motion.update(expanded, screen: NSScreen.main) }
        // The installed loop is six seconds. Finish this check before the playback watchdog can expire.
        DispatchQueue.main.asyncAfter(deadline: .now()+7.5) {
            let lockedMotionSettled = !lockMotion.isAnimating && abs(lockMotion.surface.height - expanded.height) < 0.1
            let motionSettled = !motion.isAnimating && abs(motion.surface.width-expanded.width) < 0.1
            let airPodsNoticeExpired = musicLayout.notices.current == nil && musicLayout.notices.pending.isEmpty
            let inlineNoticeExpired = inlineLayout.notices.current == nil
            playbackWindow.orderOut(nil)
            inlineLayout.stop()
            musicLayout.stop()
            chargingLayout.stop()
            staggered.stop()
            window.orderOut(nil)
            morphModel.stop()
            let airPodsMorphPassed = sawIntermediateWidth && reopened && collapsedAgain && disconnected
            let diagnostics: [String: Any] = [
                "airPodsMorphIntermediate": sawIntermediateWidth, "airPodsMorphReopened": reopened,
                "airPodsMorphCollapsed": collapsedAgain, "airPodsMorphDisconnected": disconnected,
                "volumeReplacesMusic": volumeReplacesMusic, "volumeReplacesExpanded": volumeReplacesExpanded, "brightnessReplacesExpanded": brightnessReplacesExpanded,
                "inlineAirPodsDetails": inlineAirPodsExpanded && inlineAirPodsCollapsed,
                "volumeReplacesMusicWithNotices": volumeReplacesMusicWithNotices,
                "pausedPlayerUsesBrightnessOSD": pausedPlayerUsesBrightnessOSD, "osdRestoresExpanded": osdRestoresExpanded,
                "volumeReplacesNotice": volumeReplacesNotice,
                "chargingTakesCenter": chargingTakesCenter, "lockedChargingTakesCenter": lockedChargingTakesCenter,
                "chargingRestoresPlayer": chargingRestoresPlayer, "chargingInterruptsNotice": chargingInterruptsNotice,
                "chargingRestoresNotice": chargingRestoresNotice,
                "nativeCombinedWins": nativeCombinedWins, "missingCombinedUsesEarbuds": missingCombinedUsesEarbuds,
                "unavailableChargeStaysUnknown": unavailableChargeStaysUnknown,
                "musicKeepsCenter": musicKeepsCenter, "musicKeepsBatteryReading": musicKeepsBatteryReading,
                "airPodsNoticeExpired": airPodsNoticeExpired,
                "airPodsSurvivesOldCutoff": survivesOldCutoff, "inlineAirPodsExpired": inlineNoticeExpired,
                "testedNativeAirPodsMovie": expectsMovie,
                "trackChangeStaysCollapsed": trackChangeStaysCollapsed,
                "coverFlipFollowsSkipDirection": nextFlipsForward && previousFlipsBackward && !model.media.artworkFlipsBackward,
                "noticeDisplacesMedia": noticeDisplacesMedia, "bubbleRestoresMedia": bubbleRestoresMedia,
                "lockedCollapses": lockedCollapses, "unlockRestoresExpansion": unlockRestoresExpansion,
                "unlockKeepsPlayerAndLockBubble": unlockKeepsPlayerAndLockBubble,
                "lockedPlayerOpens": lockedPlayerOpens && lockedPlayerExpands,
                "lockedPlayerCloses": lockedPlayerCloses,
                "lockedBubblesActivities": lockedBubblesActivities,
                "lockedVolumeVisible": lockedVolumeVisible, "lockedBrightnessVisible": lockedBrightnessVisible,
                "lockedMotionSettled": lockedMotionSettled,
                "motionSettled": motionSettled, "motionFrames": motion.frameCount,
                "finalWidth": motion.surface.width, "finalHeight": motion.surface.height,
                "result": motionSettled && lockedMotionSettled && lockedBrightnessVisible && volumeReplacesMusic && volumeReplacesExpanded && brightnessReplacesExpanded && pausedPlayerUsesBrightnessOSD && osdRestoresExpanded
                    && inlineAirPodsExpanded && inlineAirPodsCollapsed
                    && volumeReplacesMusicWithNotices
                    && trackChangeStaysCollapsed && nextFlipsForward && previousFlipsBackward
                    && noticeDisplacesMedia && bubbleRestoresMedia
                    && lockedCollapses && lockedBubblesActivities && lockedVolumeVisible && unlockKeepsPlayerAndLockBubble && lockedPlayerOpens && lockedPlayerExpands && lockedPlayerCloses
                    && unlockRestoresExpansion && volumeReplacesNotice
                    && survivesOldCutoff && inlineNoticeExpired && chargingInterruptsNotice && chargingRestoresNotice
                    && chargingTakesCenter && lockedChargingTakesCenter && chargingRestoresPlayer && musicKeepsCenter && musicKeepsBatteryReading && airPodsNoticeExpired && airPodsMorphPassed && nativeCombinedWins && missingCombinedUsesEarbuds && unavailableChargeStaysUnknown ? "pass" : "fail",
                "scope": "Actual app models and renderer with preview media; no external player commands."
            ]
            if let data = try? JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output.appendingPathComponent("result.json"))
                print(String(decoding: data, as: UTF8.self))
            }
            motion.stop(); model.stop(); defaults.removePersistentDomain(forName: suite)
            NSApp.terminate(nil)
        }
    }
    private static func render(_ model: NotchModel, _ output: URL, width: CGFloat = 540) {
        let view = NotchRootView(model: model).environment(\.staticNotchPreview, true)
            .frame(width: width, height: 310, alignment: .top).clipped()
            .background(Color(red: 0.13, green: 0.16, blue: 0.2))
        let renderer = ImageRenderer(content: view); renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: output)
    }
}
