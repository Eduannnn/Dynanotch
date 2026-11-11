import Foundation

public enum HardwareMediaKey: UInt16, Hashable, Sendable {
    case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
}

/// NX_SUBTYPE_AUX_CONTROL_BUTTONS carries paired down/up events and autorepeat.
/// Other system-defined events, playback keys, and keyboard backlight keys pass through.
public struct HardwareMediaKeyStroke: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case down, up }
    public let key: HardwareMediaKey
    public let phase: Phase
    public let isRepeat: Bool

    public static func decode(subtype: Int16, data1: Int) -> Self? {
        guard subtype == 8 else { return nil }
        let bits = UInt32(truncatingIfNeeded: data1)
        guard let key = HardwareMediaKey(rawValue: UInt16(bits >> 16)) else { return nil }
        let state = (bits >> 8) & 0xff
        guard state == 0x0a || state == 0x0b else { return nil }
        return Self(key: key, phase: state == 0x0a ? .down : .up, isRepeat: bits & 1 != 0)
    }
}

/// Consume a release only if its matching press was handled successfully.
public struct MediaKeyCapture {
    private var pressed: Set<HardwareMediaKey> = []
    public init() {}

    public mutating func route(_ stroke: HardwareMediaKeyStroke, eligible: Bool, perform: (HardwareMediaKey) -> Bool) -> Bool {
        if stroke.phase == .up { return pressed.remove(stroke.key) != nil }
        guard eligible, perform(stroke.key) else { pressed.remove(stroke.key); return false }
        pressed.insert(stroke.key)
        return true
    }
    public mutating func reset() { pressed.removeAll() }
}

public func hardwareLevelStep(_ current: Double, increasing: Bool, fine: Bool) -> Double {
    unit(unit(current) + (increasing ? 1 : -1) / (fine ? 64 : 16))
}

/// Move to the next volume tick in the requested direction. Audio devices can
/// report a rounded scalar after a write, so treat a read near a tick as that
/// tick rather than carrying the rounding error into the next adjustment.
public func hardwareVolumeStep(_ current: Double, increasing: Bool, fine: Bool) -> Double {
    let ticks = fine ? 64.0 : 16.0
    let level = unit(current)
    let nearest = (level * ticks).rounded()
    let aligned = abs(level - nearest / ticks) <= 0.003
    let next = aligned ? nearest + (increasing ? 1 : -1) : (increasing ? ceil(level * ticks) : floor(level * ticks))
    return unit(next / ticks)
}
