import Foundation

public func unit(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }

public struct TrackIdentity: Equatable, Sendable {
    public var source: String
    public var identifier: String
    public var title: String
    public var artist: String
    public var album: String

    public init(source: String, identifier: String = "", title: String, artist: String = "", album: String = "") {
        self.source = source; self.identifier = identifier
        self.title = title; self.artist = artist; self.album = album
    }

    public func isSameTrack(as other: TrackIdentity) -> Bool {
        guard source == other.source else { return false }
        if !identifier.isEmpty && !other.identifier.isEmpty { return identifier == other.identifier }
        return title == other.title && artist == other.artist && album == other.album
    }
}

public func seekPosition(fraction: Double, duration: Double) -> Double? {
    guard fraction.isFinite, duration.isFinite, duration > 0 else { return nil }
    return min(max(0, duration - 0.01), unit(fraction) * duration)
}

public func clockText(_ seconds: Double) -> String {
    let value = seconds.isFinite ? Int(max(0, min(seconds, 864_000))) : 0
    return "\(value / 60):\(String(format: "%02d", value % 60))"
}

public enum NoticeKind: String, Codable, Sendable {
    case bluetooth, earbuds, headphones, controller, keyboard, mouse, speaker, phone, usb
    case charging, batteryLow, batteryCritical

    public var symbol: String {
        switch self {
        case .bluetooth: "antenna.radiowaves.left.and.right"
        case .earbuds: "airpodspro"
        case .headphones: "headphones"
        case .controller: "gamecontroller.fill"
        case .keyboard: "keyboard.fill"
        case .mouse: "computermouse.fill"
        case .speaker: "hifispeaker.fill"
        case .phone: "iphone"
        case .usb: "cable.connector"
        case .charging: "bolt.fill"
        case .batteryLow, .batteryCritical: "battery.25percent"
        }
    }

    public var isPower: Bool { [.charging, .batteryLow, .batteryCritical].contains(self) }

    public static func device(named name: String, fallback: NoticeKind = .bluetooth) -> NoticeKind {
        let text = name.lowercased()
        if ["controller", "gamepad", "dualsense", "xbox", "joy-con"].contains(where: text.contains) { return .controller }
        if text.contains("airpods max") { return .headphones }
        if ["airpod", "earbud", "buds"].contains(where: text.contains) { return .earbuds }
        if ["headphone", "headset"].contains(where: text.contains) { return .headphones }
        if text.contains("keyboard") { return .keyboard }
        if text.contains("mouse") || text.contains("trackpad") { return .mouse }
        if text.contains("speaker") { return .speaker }
        if text.contains("phone") { return .phone }
        return fallback
    }
}

/// Product-family artwork only; unrelated earbuds/headphones retain their SF Symbols.
public enum AirPodsFamily: String, CaseIterable, Hashable, Sendable {
    case airpods, airpodsPro, airpodsMax
    public var bannerProductID: Int {
        switch self { case .airpods: 8194; case .airpodsPro: 8206; case .airpodsMax: 8202 }
    }
    public static func matching(name: String) -> AirPodsFamily? {
        let normalized = name.lowercased().filter { $0.isLetter || $0.isNumber }
        guard normalized.contains("airpod") else { return nil }
        if normalized.contains("airpodsmax") || normalized.contains("airpodmax") { return .airpodsMax }
        if normalized.contains("airpodspro") || normalized.contains("airpodpro") { return .airpodsPro }
        return .airpods
    }
}

/// Device metadata wins over a user-editable Bluetooth name.
public struct AirPodsArtwork: Hashable, Sendable {
    public var family: AirPodsFamily
    public var productID: Int
    public var colorID: Int?
    public init(family: AirPodsFamily, productID: Int? = nil, colorID: Int? = nil) {
        self.family = family
        self.productID = productID ?? family.bannerProductID
        self.colorID = colorID.flatMap { (0...255).contains($0) ? $0 : nil }
    }
    public static func resolve(name: String, vendorID: Int?, productID: Int?, colorID: Int?) -> Self? {
        // Apple Bluetooth and USB vendor IDs, respectively. Never assign Apple's
        // movies to a positively identified third-party device using its name.
        if let vendorID, vendorID != 0, vendorID != 0x004c, vendorID != 0x05ac { return nil }
        let family: AirPodsFamily?
        switch productID {
        case 0x200a, 0x201f, 0x202d: family = .airpodsMax
        case 0x200e, 0x2014, 0x2024, 0x2027: family = .airpodsPro
        case 0x2002, 0x200f, 0x2013, 0x2019, 0x201b, 0x2030, 0x2032, 0x2036, 0x2037: family = .airpods
        default: family = nil
        }
        if let family, let vendorID, vendorID == 0x004c || vendorID == 0x05ac {
            return Self(family: family, productID: productID, colorID: colorID)
        }
        guard let fallback = AirPodsFamily.matching(name: name) else { return nil }
        // Unverified metadata cannot select a model-specific or coloured asset.
        return Self(family: fallback)
    }
    public var movieRelativePaths: [String] {
        var result: [String] = []
        func add(_ pid: Int, _ suffix: String) {
            result.append("Banner-PID-\(pid)-mov/Banner-PID-\(pid)\(suffix)-Loop.mov")
        }
        if let colorID {
            // Apple's catalogue maps 0 and 15 to the same original Max black.
            let color = productID == 8202 && colorID == 0 ? 15 : colorID
            add(productID, "-\(color)")
        }
        add(productID, "-default")
        add(productID, "")
        if productID != family.bannerProductID {
            // A missing newer-model movie falls back to family artwork, without
            // pretending a colour code from another generation is compatible.
            add(family.bannerProductID, "-default")
            add(family.bannerProductID, "")
        }
        return result
    }
}

public struct DeviceNotice: Equatable, Identifiable, Sendable {
    public var id: String { key + (connected ? "/on" : "/off") }
    public var key: String
    public var name: String
    public var kind: NoticeKind
    public var transport: String
    public var connected: Bool
    public var battery: Double?
    public var airPodsArtwork: AirPodsArtwork?

    public init(key: String, name: String, kind: NoticeKind, transport: String = "Bluetooth", connected: Bool = true, battery: Double? = nil, airPodsArtwork: AirPodsArtwork? = nil) {
        self.key = key; self.name = name; self.kind = kind; self.transport = transport; self.connected = connected
        self.airPodsArtwork = airPodsArtwork
        self.battery = battery.flatMap { $0.isFinite && (0...1).contains($0) && connected ? $0 : nil }
    }
}

/// A bounded queue shared by battery, Bluetooth and USB notices. OSDs temporarily hold it.
public struct NoticeQueue: Sendable {
    public private(set) var current: DeviceNotice?
    public private(set) var pending: [DeviceNotice] = []
    public init() {}

    @discardableResult public mutating func enqueue(_ notice: DeviceNotice) -> Bool {
        let last = pending.last ?? current
        if last?.key == notice.key && last?.connected == notice.connected {
            updateBattery(key: notice.key, level: notice.battery)
            updateArtwork(key: notice.key, artwork: notice.airPodsArtwork)
            return false
        }
        if current == nil { current = notice } else {
            pending.append(notice)
            if pending.count > 8 { pending.removeFirst(pending.count - 8) }
        }
        return true
    }

    public mutating func advance() { current = pending.isEmpty ? nil : pending.removeFirst() }
    public mutating func expire(id: DeviceNotice.ID) {
        if current?.id == id {
            advance()
        } else if let index = pending.firstIndex(where: { $0.id == id }) {
            pending.remove(at: index)
        }
    }
    public mutating func dismiss(key: String) {
        pending.removeAll { $0.key == key }
        if current?.key == key { advance() }
    }
    public mutating func updateArtwork(key: String, artwork: AirPodsArtwork?) {
        guard let artwork else { return }
        if current?.key == key { current?.airPodsArtwork = artwork }
        for i in pending.indices where pending[i].key == key { pending[i].airPodsArtwork = artwork }
    }
    public mutating func updateBattery(key: String, level: Double?) {
        let valid = level.flatMap { $0.isFinite && (0...1).contains($0) ? $0 : nil }
        if var notice = current, notice.key == key { notice.battery = notice.connected ? valid : nil; current = notice }
        for i in pending.indices where pending[i].key == key { pending[i].battery = pending[i].connected ? valid : nil }
    }
}

public enum Presentation: String, Sendable {
    case idle, collapsed, peek, expanded, notice, osd
    public static func resolve(osd: Bool, notice: Bool, media: Bool, hovered: Bool, scrubbing: Bool, peek: Bool) -> Presentation {
        if osd { return .osd }
        if notice { return .notice }
        guard media else { return .idle }
        if hovered || scrubbing { return .expanded }
        return peek ? .peek : .collapsed
    }
}

public struct RGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = unit(r); self.g = unit(g); self.b = unit(b) }
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
    public var readable: RGB {
        guard luminance < 0.22 else { return self }
        let peak = max(r, g, b)
        var bright = peak > 0 ? RGB(r / peak, g / peak, b / peak) : self
        if bright.luminance >= 0.22 && peak > 0 {
            var low = 1.0, high = 1 / peak
            for _ in 0..<14 {
                let mid = (low + high) / 2
                if RGB(r * mid, g * mid, b * mid).luminance < 0.22 { low = mid } else { high = mid }
            }
            return RGB(r * high, g * high, b * high)
        }
        var low = 0.0, high = 1.0
        for _ in 0..<14 {
            let mix = (low + high) / 2
            let candidate = RGB(bright.r + (1 - bright.r) * mix, bright.g + (1 - bright.g) * mix, bright.b + (1 - bright.b) * mix)
            if candidate.luminance < 0.22 { low = mix } else { high = mix }
        }
        bright = RGB(bright.r + (1 - bright.r) * high, bright.g + (1 - bright.g) * high, bright.b + (1 - bright.b) * high)
        return bright
    }
}
