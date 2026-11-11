import Foundation

/// App-owned countdown; the host supplies its clock. Persisted deadlines recover after relaunch.
public struct Countdown: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case idle, running, paused, finished }
    public private(set) var phase: Phase = .idle
    public private(set) var duration: TimeInterval = 0
    public private(set) var deadline: Date?
    public private(set) var pausedRemaining: TimeInterval = 0
    public init() {}
    public var exists: Bool { phase != .idle }

    @discardableResult public mutating func start(seconds: TimeInterval, at now: Date) -> Bool {
        guard seconds.isFinite, seconds >= 1, seconds <= 86_400 else { return false }
        duration = seconds; pausedRemaining = seconds
        deadline = now.addingTimeInterval(seconds); phase = .running
        return true
    }
    public func remaining(at now: Date) -> TimeInterval {
        if phase == .running, let deadline { return min(duration, max(0, deadline.timeIntervalSince(now))) }
        return phase == .paused ? pausedRemaining : 0
    }
    public mutating func pause(remaining: TimeInterval) {
        guard phase == .running, remaining.isFinite else { return }
        pausedRemaining = min(duration, max(0, remaining)); deadline = nil
        phase = pausedRemaining > 0 ? .paused : .finished
    }
    public mutating func resume(at now: Date) {
        guard phase == .paused, pausedRemaining > 0 else { return }
        deadline = now.addingTimeInterval(pausedRemaining); phase = .running
    }
    public mutating func finish() {
        guard phase == .running else { return }
        phase = .finished; deadline = nil; pausedRemaining = 0
    }
    public mutating func cancel() { self = Countdown() }
    public mutating func synchronizeDeadline(remaining: TimeInterval, at now: Date) {
        guard phase == .running, remaining.isFinite, remaining > 0 else { return }
        deadline = now.addingTimeInterval(min(duration, remaining))
    }
    public mutating func restart(at now: Date) { _ = start(seconds: duration, at: now) }
}

/// Closed-form damped spring. Retargeting changes the destination, preserving position and velocity.
public struct MotionValue: Sendable {
    public var value: Double
    public var velocity: Double = 0
    public var target: Double
    public init(_ value: Double) { self.value = value; target = value }
    public mutating func advance(seconds dt: Double, response: Double = 0.32, damping: Double = 0.88) {
        guard dt.isFinite, dt > 0, response > 0 else { return }
        let w = 2 * Double.pi / response
        let z = min(0.999, max(0.01, damping)), a = z*w, wd = w*sqrt(1-z*z)
        let displacement = value-target, b = (velocity+a*displacement)/wd
        let c = cos(wd*dt), s = sin(wd*dt), e = exp(-a*dt)
        value = target + e*(displacement*c+b*s)
        velocity = e*(-a*(displacement*c+b*s)+wd*(-displacement*s+b*c))
    }
    public var settled: Bool { abs(value-target) < 0.08 && abs(velocity) < 0.8 }
    public mutating func settle() { value = target; velocity = 0 }
}
