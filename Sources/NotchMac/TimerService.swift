import AppKit
import Combine
import UserNotifications
import NotchCore

@MainActor final class TimerService: ObservableObject {
    @Published private(set) var state = Countdown()
    @Published private(set) var remaining: Double = 0
    @Published private(set) var notificationMessage = ""
    var onFinished: (() -> Void)?
    private var ticker: Timer?
    private var anchor: ContinuousClock.Instant?
    private var anchorRemaining: Double = 0
    private var wake: NSObjectProtocol?
    private let defaults: UserDefaults
    private let allowsNotifications: Bool
    private var notificationTask: Task<Void, Never>?
    private let storageKey = "dynanotch.ownCountdown.v1"
    private var notificationID: String

    init(defaults: UserDefaults = .standard, allowsNotifications: Bool = true) {
        self.defaults = defaults; self.allowsNotifications = allowsNotifications
        notificationID = defaults.string(forKey: "dynanotch.timerNotificationID") ?? "dynanotch.ownCountdown.finished"
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(Countdown.self, from: data),
           saved.duration.isFinite, (0...86_400).contains(saved.duration) {
            state = saved; remaining = saved.remaining(at: Date())
            if state.phase == .running && remaining <= 0 { state.finish() }
            if state.phase == .running { beginClock() }
        }
        wake = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }
    var exists: Bool { state.exists }
    var displayTime: String { clockText(ceil(remaining)) }
    var progress: Double { state.duration > 0 ? unit(1-remaining/state.duration) : 0 }

    func start(seconds: Double, notifications: Bool = true) {
        guard state.start(seconds: seconds, at: Date()) else { return }
        remaining = seconds; beginClock(); persist()
        if notifications && allowsNotifications { scheduleNotification() }
    }
    func togglePause() {
        if state.phase == .running {
            tick(); state.pause(remaining: remaining); ticker?.invalidate(); ticker = nil; anchor = nil
            cancelNotification()
        } else if state.phase == .paused {
            state.resume(at: Date()); beginClock(); if allowsNotifications { scheduleNotification() }
        }
        persist()
    }
    func restart() { start(seconds: state.duration) }
    func cancel() {
        state.cancel(); remaining = 0; anchor = nil; ticker?.invalidate(); ticker = nil
        cancelNotification()
        if allowsNotifications { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationID]) }
        persist()
    }
    private func beginClock() {
        ticker?.invalidate(); anchor = .now; anchorRemaining = remaining
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker?.tolerance = 0.08
    }
    private func tick() {
        guard state.phase == .running, let anchor else { return }
        let elapsed = anchor.duration(to: .now).components
        remaining = max(0, anchorRemaining-Double(elapsed.seconds)-Double(elapsed.attoseconds)/1e18)
        if remaining == 0 {
            state.finish(); ticker?.invalidate(); ticker = nil; self.anchor = nil
            persist(); onFinished?()
        }
    }
    private func persist() {
        if state.phase == .running { state.synchronizeDeadline(remaining: remaining, at: Date()) }
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: storageKey) }
    }
    private func cancelNotification() {
        notificationTask?.cancel(); notificationTask = nil
        if allowsNotifications { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID]) }
    }
    private func scheduleNotification() {
        cancelNotification()
        notificationID = "dynanotch.ownCountdown.finished." + UUID().uuidString
        defaults.set(notificationID, forKey: "dynanotch.timerNotificationID")
        let id = notificationID
        notificationTask = Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if settings.authorizationStatus == .notDetermined {
                allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            }
            guard !Task.isCancelled, id == notificationID, state.phase == .running else { return }
            guard allowed else {
                notificationMessage = "Timer works in the notch. Allow notifications for background alerts."; return
            }
            let content = UNMutableNotificationContent()
            content.title = "Timer finished"; content.body = "Your Dynanotch timer is complete."; content.sound = .default
            let request = UNNotificationRequest(identifier: id, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false))
            do {
                try await center.add(request)
                if Task.isCancelled || id != notificationID { center.removePendingNotificationRequests(withIdentifiers: [id]) }
                else { notificationMessage = "" }
            }
            catch { notificationMessage = "Background notification could not be scheduled." }
        }
    }
    func stop() {
        tick(); persist(); ticker?.invalidate(); ticker = nil
        if let wake { NSWorkspace.shared.notificationCenter.removeObserver(wake) }
    }
}
