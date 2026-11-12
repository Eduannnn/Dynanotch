import AppKit
import SwiftUI
import NotchCore

/// Runs the real models and renderer with isolated preferences and no device/media side effects.
@MainActor enum AppVerification {
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
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "com.eduannnn.dynanotch.visual-check." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let model = NotchModel(preferences: Preferences(defaults: defaults))
        model.cameraWidth = 208; model.cameraHeight = 37.5; model.availableWidth = 1710
        model.displayScreen = NSScreen.main
        model.media.setPreview(true); model.pinned = true; model.hovering = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Dynanotch · cover-turn visual check"
        window.contentView = NSHostingView(rootView: NotchRootView(model: model)
            .frame(width: 540, height: 280, alignment: .top).clipped()
            .background(Color(red: 0.13, green: 0.16, blue: 0.2)))
        window.center(); window.makeKeyAndOrderFront(nil)
        let ready: [String: Any] = ["windowID": window.windowNumber, "readyTime": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: ready) { try? data.write(to: output.appendingPathComponent("ready.json")) }
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
        let compact = model.surfaceTarget
        render(model, output.appendingPathComponent("music-compact.png"))
        let compactCoverX = -model.bodyWidth/2+model.bodyOffset+model.surfaceTarget.artworkX
        model.osd = .init(kind: .volume, level: 0.6, muted: false)
        let volumeCoverX = -model.bodyWidth/2+model.bodyOffset+model.surfaceTarget.artworkX
        let volumeKeepsCover = model.preservesMediaArtwork && abs(compactCoverX-volumeCoverX) < 0.001
        render(model, output.appendingPathComponent("music-volume-compact.png"))
        model.pinned = true; model.hovering = true
        let volumeKeepsExpanded = model.presentation == .expanded
        render(model, output.appendingPathComponent("music-volume-expanded.png"))
        model.media.command("playpause")
        let pausedVolumeUsesIcon = !model.preservesMediaArtwork && model.presentation == .osd
        model.osd = nil; model.media.command("playpause")
        model.media.command("playpause")
        model.close(); model.previewNotice()
        let noticeDisplacesMedia = model.presentation == .notice && model.showsMediaBubble
            && model.surfaceTarget.artworkX < 0
        render(model, output.appendingPathComponent("notice-with-media-bubble.png"))
        model.osd = .init(kind: .volume, level: 0.6, muted: false)
        let volumePillPreservesNotice = model.trailingVolume?.level == 0.6
            && model.presentation == .notice && model.showsMediaBubble
        render(model, output.appendingPathComponent("notice-with-volume-pill.png"))
        model.osd = nil
        model.previewCharging()
        let airPodsFirst = model.mainNotice?.airPodsArtwork != nil
            && model.trailingCharge?.kind == .charging && model.showsMediaBubble
        render(model, output.appendingPathComponent("airpods-with-charging-pill.png"))
        model.activateBubble()
        model.previewCharging()
        model.previewNotice()
        let chargerFirst = model.mainNotice?.airPodsArtwork != nil
            && model.trailingCharge?.kind == .charging && model.showsMediaBubble
        model.osd = .init(kind: .volume, level: 0.6, muted: false)
        let pairedNoticeKeepsVolumeSeparate = model.trailingVolume != nil
            && model.volumePillExtraOffset == NotchModel.chargePillWidth + NotchModel.volumePillGap
        model.activateBubble()
        let bubbleRestoresMedia = model.presentation == .expanded && model.notices.current == nil && !model.showsMediaBubble
        model.media.command("playpause")
        let musicLayout = NotchModel(preferences: Preferences(defaults: defaults))
        musicLayout.cameraWidth = 208; musicLayout.cameraHeight = 37.5; musicLayout.availableWidth = 1710
        musicLayout.media.setPreview(true)
        musicLayout.previewCharging()
        musicLayout.previewNotice(battery: nil)
        let musicKeepsCenter = musicLayout.presentation == .collapsed && !musicLayout.showsMediaBubble
            && musicLayout.leadingAirPods?.airPodsArtwork != nil && musicLayout.leadingAirPods?.battery == nil
            && musicLayout.trailingCharge?.kind == .charging
        render(musicLayout, output.appendingPathComponent("music-with-airpods-and-charging.png"))
        musicLayout.previewNotice(battery: 0.75)
        render(musicLayout, output.appendingPathComponent("airpods-connected-with-music-and-charging.png"))
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
        morphModel.previewCharging()
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
                    && morphModel.surfaceTarget == centerBeforeMorph && morphModel.trailingCharge != nil
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
        var chargeExpiresFirst = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.25) {
            chargeExpiresFirst = musicLayout.trailingCharge == nil && musicLayout.leadingAirPods != nil
        }
        model.screenLocked = true
        let lockedCollapses = model.presentation == .collapsed
        model.screenLocked = false
        let unlockRestoresExpansion = model.presentation == .expanded
        let motion = NotchAnimationCoordinator()
        let expanded = NotchSurface(width: 400, height: 193.5, offset: 0, radius: 30, ear: 12)
        motion.update(compact, screen: NSScreen.main, immediate: true)
        motion.update(expanded, screen: NSScreen.main)
        DispatchQueue.main.asyncAfter(deadline: .now()+0.08) { motion.update(compact, screen: NSScreen.main) }
        DispatchQueue.main.asyncAfter(deadline: .now()+0.16) { motion.update(expanded, screen: NSScreen.main) }
        // The installed loop is six seconds. Finish this check before the playback watchdog can expire.
        DispatchQueue.main.asyncAfter(deadline: .now()+7.5) {
            let motionSettled = !motion.isAnimating && abs(motion.surface.width-expanded.width) < 0.1
            let bothNoticesExpired = musicLayout.notices.current == nil && musicLayout.notices.pending.isEmpty
            let inlineNoticeExpired = inlineLayout.notices.current == nil
            playbackWindow.orderOut(nil)
            inlineLayout.stop()
            musicLayout.stop()
            window.orderOut(nil)
            morphModel.stop()
            let airPodsMorphPassed = sawIntermediateWidth && reopened && collapsedAgain && disconnected
            let diagnostics: [String: Any] = [
                "airPodsMorphIntermediate": sawIntermediateWidth, "airPodsMorphReopened": reopened,
                "airPodsMorphCollapsed": collapsedAgain, "airPodsMorphDisconnected": disconnected,
                "volumeKeepsCover": volumeKeepsCover, "volumeKeepsExpanded": volumeKeepsExpanded,
                "pausedVolumeUsesIcon": pausedVolumeUsesIcon,
                "volumePillPreservesNotice": volumePillPreservesNotice,
                "airPodsFirst": airPodsFirst, "chargerFirst": chargerFirst,
                "nativeCombinedWins": nativeCombinedWins, "missingCombinedUsesEarbuds": missingCombinedUsesEarbuds,
                "unavailableChargeStaysUnknown": unavailableChargeStaysUnknown,
                "musicKeepsCenter": musicKeepsCenter, "musicKeepsBatteryReading": musicKeepsBatteryReading,
                "chargeExpiresFirst": chargeExpiresFirst, "bothNoticesExpired": bothNoticesExpired,
                "airPodsSurvivesOldCutoff": survivesOldCutoff, "inlineAirPodsExpired": inlineNoticeExpired,
                "testedNativeAirPodsMovie": expectsMovie,
                "pairedNoticeKeepsVolumeSeparate": pairedNoticeKeepsVolumeSeparate,
                "trackChangeStaysCollapsed": trackChangeStaysCollapsed,
                "noticeDisplacesMedia": noticeDisplacesMedia, "bubbleRestoresMedia": bubbleRestoresMedia,
                "lockedCollapses": lockedCollapses, "unlockRestoresExpansion": unlockRestoresExpansion,
                "motionSettled": motionSettled, "motionFrames": motion.frameCount,
                "finalWidth": motion.surface.width, "finalHeight": motion.surface.height,
                "result": motionSettled && volumeKeepsCover && volumeKeepsExpanded && pausedVolumeUsesIcon
                    && trackChangeStaysCollapsed && noticeDisplacesMedia && bubbleRestoresMedia
                    && lockedCollapses && unlockRestoresExpansion && volumePillPreservesNotice
                    && survivesOldCutoff && inlineNoticeExpired
                    && airPodsFirst && chargerFirst && pairedNoticeKeepsVolumeSeparate && musicKeepsCenter && musicKeepsBatteryReading && chargeExpiresFirst && bothNoticesExpired && airPodsMorphPassed && nativeCombinedWins && missingCombinedUsesEarbuds && unavailableChargeStaysUnknown ? "pass" : "fail",
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
