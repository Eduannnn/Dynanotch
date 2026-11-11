import Foundation

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
