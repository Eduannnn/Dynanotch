import AppKit
import SwiftUI
import Combine
import NotchCore

struct SystemOSD: Equatable {
    enum Kind { case volume, brightness }
    var kind: Kind
    var level: Double
    var muted: Bool
    var symbol: String {
        if kind == .brightness { return "sun.max.fill" }
        return muted || level == 0 ? "speaker.slash.fill" : level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
    var label: String { muted ? "Muted" : "\(Int(unit(level) * 100))%" }
}

@MainActor final class NotchModel: ObservableObject {
    let preferences: Preferences
    let media = MediaService()
    let timer: TimerService
    enum Activity: String { case media, timer }
    @Published private(set) var selectedActivity: Activity = .media
    enum SettingsTab: Hashable { case general, activities, calibration, media }
    @Published var settingsTab: SettingsTab = .general
    @Published var pinned = false
    let audio = AudioService()
    let brightness = BrightnessService()
    let system = SystemService()
    let waveform = WaveformService()
    let mediaKeys = MediaKeyService()
    @Published var cameraWidth: CGFloat = 180
    @Published var cameraHeight: CGFloat = 32
    @Published var availableWidth: CGFloat = 1280
    @Published var hovering = false
    @Published var scrubbing = false
    @Published var peek = false
    @Published var previewMode = false
    @Published var osd: SystemOSD?
    @Published private(set) var notices = NoticeQueue()
    @Published var hidden = false
    @Published var screenLocked = false
    var configuredWindowLevel = 0
    var configuredVisibleWithoutLogin = false
    var lockEventCount = 0
    var lastLockedWindowLevel: Int?
    @Published var calibrating = false
    var openSettings: (() -> Void)?
    var restartApp: (() -> Void)?
    var displayScreen: NSScreen?
    var presentedSurface: NotchSurface?
    var onSurfaceChanged: (() -> Void)?
    @Published var edgeLighting = EdgeLighting()
    @Published var bubbleLighting = EdgeLighting()
    var pointerIsInteractive = false
    private(set) var artworkTurns = 0
    private(set) var artworkTurnPhase = "idle"
    func recordArtworkTurn(_ phase: String) {
        artworkTurnPhase = phase
        if phase == "outgoing" { artworkTurns += 1 }
    }
    private var subscriptions = Set<AnyCancellable>()
    private var collapseWork: DispatchWorkItem?
    private var peekWork: DispatchWorkItem?
    private var osdWork: DispatchWorkItem?
    private var noticeTimer: Timer?
    @Published private(set) var previewAirPodsBatteryDetails: AirPodsBatteryDetails?
    @Published private(set) var heldAirPodsNotice: DeviceNotice.ID?
    private var noticeDeadlines: [DeviceNotice.ID: TimeInterval] = [:]
    private var pointerInside = false
    // Keep the upstream QML's uiScale (0.58), panel dimensions and calibrated 2 pt safety inset.
    let uiScale: CGFloat = 0.58
    var expandedWidth: CGFloat { 360 }
    var expandedSafeTop: CGFloat { max(0, cameraHeight + 2 - 37 * uiScale) }
    private var pairedConnectionNotices: (charging: DeviceNotice, airPods: DeviceNotice)? {
        guard preferences.showNotices, let first = notices.current,
              let second = notices.pending.first else { return nil }
        if first.kind == .charging, second.connected, second.airPodsArtwork != nil {
            return (first, second)
        }
        if second.kind == .charging, first.connected, first.airPodsArtwork != nil {
            return (second, first)
        }
        return nil
    }

    var mainNotice: DeviceNotice? { pairedConnectionNotices?.airPods ?? notices.current }

    private var musicHasConnectionNotice: Bool {
        guard preferences.showNotices, !screenLocked,
              media.snapshot?.isPlaying == true, let notice = mainNotice else { return false }
        return notice.kind == .charging || (notice.connected && notice.airPodsArtwork != nil)
    }

    var leadingAirPods: DeviceNotice? {
        guard musicHasConnectionNotice, let notice = mainNotice,
              notice.connected, notice.airPodsArtwork != nil else { return nil }
        return notice
    }
    static let airPodsPillSize: CGFloat = 34
    static let airPodsExpandedWidth: CGFloat = 204
    var airPodsSatelliteWidth: CGFloat = airPodsPillSize
    var airPodsPillOffset: CGFloat { bubbleActivity == nil ? 42 : 84 }
    @Published var airPodsPillLighting = EdgeLighting()

    var trailingCharge: DeviceNotice? {
        if musicHasConnectionNotice {
            return pairedConnectionNotices?.charging ?? (mainNotice?.kind == .charging ? mainNotice : nil)
        }
        return presentation == .notice ? pairedConnectionNotices?.charging : nil
    }
    static let chargePillWidth: CGFloat = 56
    @Published var chargePillLighting = EdgeLighting()
    var volumePillExtraOffset: CGFloat {
        trailingCharge == nil ? 0 : Self.chargePillWidth + Self.volumePillGap
    }

    var trailingVolume: SystemOSD? {
        guard let osd, osd.kind == .volume, !screenLocked,
              musicHasConnectionNotice || pairedConnectionNotices != nil || activityBubble(for: basePresentation) != nil else { return nil }
        return osd
    }
    static let volumePillWidth: CGFloat = 77
    static let volumePillHeight: CGFloat = 34
    static let volumePillGap: CGFloat = 8
    @Published var volumePillLighting = EdgeLighting()
    var preservesMediaArtwork: Bool {
        osd?.kind == .volume && trailingVolume == nil && media.snapshot?.isPlaying == true
    }
    let compactLeadingWidth: CGFloat = 38
    let compactTrailingWidth: CGFloat = 38
    var collapsedHeight: CGFloat { cameraHeight + 2 }
    var osdLeadingWidth: CGFloat { preservesMediaArtwork ? compactLeadingWidth : 46 }
    var osdTrailingWidth: CGFloat { 55 + 22 }
    var bubbleActivity: Activity? {
        let current = presentation
        if current == .osd && preservesMediaArtwork { return timer.exists ? .timer : nil }
        return activityBubble(for: current)
    }
    // Base bubble selection is independent of volume overlay placement.
    private func activityBubble(for presentation: Presentation) -> Activity? {
        switch presentation {
        case .notice, .osd:
            if selectedActivity == .timer && timer.exists { return .timer }
            if media.snapshot != nil { return .media }
            return timer.exists ? .timer : nil
        case .timerCollapsed, .timerExpanded: return media.snapshot != nil ? .media : nil
        case .collapsed, .peek, .expanded: return timer.exists ? .timer : nil
        case .idle: return nil
        }
    }

    var presentation: Presentation {
        if osd != nil && trailingVolume == nil {
            if !screenLocked && preservesMediaArtwork && selectedActivity == .media && (hovering || pinned || scrubbing) { return .expanded }
            return .osd
        }
        return basePresentation
    }

    private var basePresentation: Presentation {
        if notices.current != nil && preferences.showNotices && !musicHasConnectionNotice { return .notice }
        if !musicHasConnectionNotice && timer.exists && (selectedActivity == .timer || media.snapshot == nil) {
            return !screenLocked && (hovering || pinned) ? .timerExpanded : .timerCollapsed
        }
        return .resolve(osd: false, notice: false, media: media.snapshot != nil, hovered: !screenLocked && (hovering || pinned), scrubbing: !screenLocked && scrubbing, peek: !screenLocked && peek)
    }
    var bodyWidth: CGFloat {
        let requested: CGFloat
        switch presentation {
        case .idle: requested = cameraWidth
        case .collapsed: requested = cameraWidth + compactLeadingWidth + compactTrailingWidth
        case .peek: requested = max(expandedWidth * 0.94, cameraWidth + 80)
        case .notice: requested = cameraWidth + noticeLeadingWidth + noticeTrailingWidth
        case .expanded: requested = max(expandedWidth, cameraWidth + 120)
        case .timerCollapsed: requested = cameraWidth + 120
        case .timerExpanded: requested = max(400, cameraWidth + 120)
        case .osd: requested = cameraWidth + osdLeadingWidth + osdTrailingWidth
        }
        return min(availableWidth - 32, requested)
    }
    var bodyHeight: CGFloat {
        switch presentation {
        case .idle, .collapsed, .osd, .notice, .timerCollapsed: collapsedHeight
        case .peek: cameraHeight + 56
        case .expanded: cameraHeight + (media.snapshot?.isBrowserAudio == true ? 84 : 138)
        case .timerExpanded: cameraHeight + 144
        }
    }
    var bodyOffset: CGFloat {
        if presentation == .collapsed { return (compactTrailingWidth - compactLeadingWidth) / 2 }
        if presentation == .timerCollapsed { return 12 }
        if presentation == .notice { return (noticeTrailingWidth - noticeLeadingWidth) / 2 }
        if presentation == .osd { return (osdTrailingWidth - osdLeadingWidth) / 2 }
        return 0
    }
    var noticeLeadingWidth: CGFloat {
        guard let notice = mainNotice, notice.kind.isPower else { return 46 }
        return ceil((notice.name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .medium)]).width) + 16
    }
    var noticeTrailingWidth: CGFloat {
        guard let notice = mainNotice else { return 0 }
        if notice.kind.isPower {
            let percent = notice.battery.map { "\(Int($0 * 100))%" } ?? ""
            let labelWidth = ceil((percent as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .semibold)]).width)
            return (notice.battery != nil ? labelWidth + 8 : 0) + 48
        }
        return notice.connected || notice.battery != nil ? 44 : 0
    }
    var radius: CGFloat { presentation == .expanded ? 70 * uiScale : presentation == .peek ? 24 : 12 }
    var earRadius: CGFloat { [.expanded, .timerExpanded].contains(presentation) ? 12 : presentation == .peek ? 8 : 6 }
    var surfaceTarget: NotchSurface {
        if bubbleActivity == .media {
            return .init(width: bodyWidth, height: bodyHeight, offset: bodyOffset,
                         radius: [.expanded, .timerExpanded].contains(presentation) ? 30 : radius,
                         ear: earRadius, artworkX: -25, artworkY: collapsedHeight / 2, artworkSize: 20)
        }
        let size: CGFloat = presentation == .expanded ? 56 : presentation == .peek ? 40 : presentation == .timerCollapsed ? 24 : min(28, cameraHeight - 4)
        let x: CGFloat = presentation == .expanded ? 46 : presentation == .peek ? 34 : presentation == .timerCollapsed ? 24 : compactLeadingWidth / 2
        let y: CGFloat = presentation == .expanded ? cameraHeight + 20 : presentation == .peek ? cameraHeight + 22 : collapsedHeight / 2
        return .init(width: bodyWidth, height: bodyHeight, offset: bodyOffset,
                     radius: [.expanded, .timerExpanded].contains(presentation) ? 30 : radius,
                     ear: earRadius, artworkX: x, artworkY: y, artworkSize: size)
    }
    func present(_ surface: NotchSurface) { presentedSurface = surface; onSurfaceChanged?() }
    var accent: Color {
        guard preferences.artworkTint, let item = media.snapshot else { return .notchAccent }
        return Color(red: item.tint.r, green: item.tint.g, blue: item.tint.b)
    }
    var secondaryAccent: Color {
        guard preferences.artworkTint, let item = media.snapshot else { return .notchAccent }
        return Color(red: item.secondaryTint.r, green: item.secondaryTint.g, blue: item.secondaryTint.b)
    }
    var motion: Animation {
        IslandMotion.shape
    }

    init(timer: TimerService? = nil, preferences: Preferences? = nil) {
        self.preferences = preferences ?? Preferences()
        self.timer = timer ?? TimerService()
        let timer = self.timer
        timer.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        timer.onFinished = { [weak self] in
            self?.selectedActivity = .timer; self?.pinned = true; self?.hovering = true
        }
        if timer.exists { selectedActivity = .timer }
        media.$snapshot.sink { [weak self] item in
            guard let self else { return }
            self.objectWillChange.send()
            if item == nil { self.peek = false }
        }.store(in: &subscriptions)
        self.preferences.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        self.preferences.$showOSD.combineLatest(self.preferences.$replaceSystemHUD, $hidden, $screenLocked)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show, replace, hidden, locked in self?.mediaKeys.configure(enabled: show && replace && !hidden && !locked) }
            .store(in: &subscriptions)
        audio.$message.combineLatest(system.$message).dropFirst().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        self.preferences.$waveformEnabled.combineLatest(
            media.$snapshot.map { $0?.isPlaying == true && $0?.isPreview == false }.removeDuplicates(), $hidden
        ).sink { [weak self] enabled, playing, hidden in
            guard let self else { return }
            if enabled && playing && !hidden { self.waveform.start() } else { self.waveform.stop() }
        }.store(in: &subscriptions)
        audio.$selectedDevice.dropFirst().removeDuplicates().sink { [weak self] _ in self?.waveform.restartIfActive() }.store(in: &subscriptions)
        audio.onVolumeChanged = { [weak self] level, muted in self?.showOSD(.init(kind: .volume, level: level, muted: muted)) }
        brightness.onChanged = { [weak self] level in self?.showOSD(.init(kind: .brightness, level: level, muted: false)) }
        mediaKeys.perform = { [weak self] key, fine in self?.handleHardwareKey(key, fine: fine) ?? false }
        system.onNotice = { [weak self] notice in self?.enqueue(notice) }
        system.onArtworkUpdated = { [weak self] key, artwork in self?.notices.updateArtwork(key: key, artwork: artwork) }
        system.onDeviceBatteryUpdated = { [weak self] key, level in self?.notices.updateBattery(key: key, level: level) }
        system.onBatteryUpdated = { [weak self] level in self?.notices.updateBattery(key: "power/system-battery", level: level) }
        system.onUnplugged = { [weak self] in self?.notices.dismiss(key: "power/system-battery"); self?.updateNoticeTimer() }
    }

    func start(demo: Bool = false) {
        audio.start(); brightness.start(); system.start()
        if demo { setPreview(true) }
        media.start()
        mediaKeys.configure(enabled: preferences.showOSD && preferences.replaceSystemHUD && !hidden && !screenLocked)
        mediaKeys.start()
    }
    func stop() { media.stop(); timer.stop(); mediaKeys.stop(); waveform.stop(); system.stop(); noticeTimer?.invalidate() }

    private func handleHardwareKey(_ key: HardwareMediaKey, fine: Bool) -> Bool {
        switch key {
        case .volumeUp, .volumeDown:
            audio.refreshNow()
            guard audio.canAdjust, audio.setVolume(hardwareVolumeStep(audio.muted ? 0 : audio.volume, increasing: key == .volumeUp, fine: fine)) else { return false }
            showOSD(.init(kind: .volume, level: audio.volume, muted: audio.muted))
        case .mute:
            audio.refreshNow()
            guard audio.setMuted(!audio.muted) else { return false }
            showOSD(.init(kind: .volume, level: audio.volume, muted: audio.muted))
        case .brightnessUp, .brightnessDown:
            brightness.refreshNow()
            guard brightness.available, brightness.adjust(hardwareLevelStep(brightness.level, increasing: key == .brightnessUp, fine: fine)) else { return false }
            showOSD(.init(kind: .brightness, level: brightness.level, muted: false))
        }
        return true
    }

    func setHover(_ inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        collapseWork?.cancel()
        if inside && preferences.expandOnHover && (media.snapshot != nil || timer.exists)
            && [.collapsed, .peek, .expanded, .timerCollapsed, .timerExpanded].contains(presentation) {
            hovering = true
        } else if !inside {
            let work = DispatchWorkItem { [weak self] in if self?.scrubbing != true && self?.pinned != true { self?.hovering = false } }
            collapseWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }

    func finishScrubbing() { scrubbing = false; if !pointerInside { hovering = false } }
    func close() {
        closeAirPodsDetails()
        pinned = false; hovering = false; peek = false; selectedActivity = timer.exists ? .timer : .media
    }
    func toggleExpansion() {
        if pinned { close() } else { pinned = true; hovering = true; peek = false }
    }
    func focusActivity(_ activity: Activity) {
        guard activity == .media ? media.snapshot != nil : timer.exists else { return }
        selectedActivity = activity; pinned = true; hovering = true; peek = false
    }
    func activateBubble() {
        guard !screenLocked, let activity = bubbleActivity else { return }
        osdWork?.cancel(); osd = nil
        noticeTimer?.invalidate(); noticeTimer = nil; notices = NoticeQueue()
        noticeDeadlines.removeAll()
        heldAirPodsNotice = nil
        focusActivity(activity)
    }
    func startTimer(seconds: Double) {
        timer.start(seconds: seconds)
        selectedActivity = .timer; pinned = false; hovering = false; peek = false
    }

    func showPeek() {
        peekWork?.cancel(); peek = true
        let work = DispatchWorkItem { [weak self] in self?.peek = false }
        peekWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    func showOSD(_ value: SystemOSD) {
        guard preferences.showOSD else { return }
        osdWork?.cancel(); osd = value; updateNoticeTimer()
        let work = DispatchWorkItem { [weak self] in self?.osd = nil; self?.updateNoticeTimer() }
        osdWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func enqueue(_ notice: DeviceNotice) {
        guard preferences.showNotices else { return }
        if !notice.connected, heldAirPodsNotice == notice.key + "/on" {
            if let id = heldAirPodsNotice { noticeDeadlines.removeValue(forKey: id) }
            heldAirPodsNotice = nil
            notices.dismiss(key: notice.key)
            notices.enqueue(notice)
            updateNoticeTimer()
            return
        }
        let hadCurrent = notices.current != nil
        let alreadyPaired = pairedConnectionNotices != nil
        notices.enqueue(notice)
        if !hadCurrent || (!alreadyPaired && pairedConnectionNotices != nil) { updateNoticeTimer() }
    }
    func toggleAirPodsDetails(_ id: DeviceNotice.ID) {
        holdAirPodsNotice(id, open: heldAirPodsNotice != id)
    }

    func closeAirPodsDetails() {
        if let id = heldAirPodsNotice { holdAirPodsNotice(id, open: false) }
    }

    func holdAirPodsNotice(_ id: DeviceNotice.ID, open: Bool) {
        if open {
            guard leadingAirPods?.id == id else { return }
            heldAirPodsNotice = id
        } else {
            guard heldAirPodsNotice == id else { return }
            heldAirPodsNotice = nil
            if let deadline = noticeDeadlines[id] {
                // Keep the compact satellite around long enough to finish the reverse spring.
                noticeDeadlines[id] = max(deadline, ProcessInfo.processInfo.systemUptime + 0.55)
            }
        }
        updateNoticeTimer()
    }

    private func updateNoticeTimer() {
        noticeTimer?.invalidate()
        noticeTimer = nil
        guard let current = notices.current, osd == nil || trailingVolume != nil else {
            noticeDeadlines.removeAll()
            return
        }

        let visible = pairedConnectionNotices.map { [$0.charging, $0.airPods] } ?? [current]
        let visibleIDs = Set(visible.map(\.id))
        noticeDeadlines = noticeDeadlines.filter { visibleIDs.contains($0.key) }
        let now = ProcessInfo.processInfo.systemUptime
        for notice in visible where noticeDeadlines[notice.id] == nil {
            let duration: TimeInterval
            if notice.kind == .charging {
                duration = 2
            } else if notice.airPodsArtwork != nil {
                duration = 3
            } else {
                duration = 4
            }
            noticeDeadlines[notice.id] = now + duration
        }
        guard let next = noticeDeadlines.filter({ $0.key != heldAirPodsNotice }).min(by: { $0.value < $1.value }) else { return }
        noticeTimer = Timer.scheduledTimer(withTimeInterval: max(0.001, next.value - now), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.noticeDeadlines.removeValue(forKey: next.key)
                self.notices.expire(id: next.key)
                self.updateNoticeTimer()
            }
        }
    }

    func setPreview(_ enabled: Bool) { previewMode = enabled; media.setPreview(enabled); if enabled { showPeek() } }
    func previewNotice(artwork: AirPodsArtwork = .init(family: .airpodsPro), battery: Double? = 0.75) {
        guard preferences.showNotices else { return }
        let key = "preview/airpods"
        if battery != nil {
            previewAirPodsBatteryDetails = artwork.family == .airpodsMax
                ? .init(headphones: 0.81)
                : .init(left: 0.68, right: 0.43, chargingCase: 0.92)
        } else {
            previewAirPodsBatteryDetails = nil
        }
        let name: String
        switch artwork.family {
        case .airpods: name = "AirPods"
        case .airpodsPro: name = "AirPods Pro"
        case .airpodsMax: name = "AirPods Max"
        }
        let replacingCurrent = notices.current?.key == key
        if let preview = ([notices.current].compactMap { $0 } + notices.pending).first(where: { $0.key == key }) {
            noticeDeadlines.removeValue(forKey: preview.id)
        }
        notices.dismiss(key: key)
        enqueue(.init(key: key, name: name, kind: artwork.family == .airpodsMax ? .headphones : .earbuds,
                      battery: previewAirPodsBatteryDetails?.listeningLevel, airPodsArtwork: artwork))
        if replacingCurrent { updateNoticeTimer() }
    }
    func previewCharging() {
        enqueue(.init(key: "preview/charging", name: "Charging", kind: .charging, transport: "Power", battery: 0.72))
    }
}
