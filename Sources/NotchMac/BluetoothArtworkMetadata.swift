import Foundation
import IOBluetooth
import ObjectiveC
import NotchCore

struct AirPodsBatteryDetails: Equatable {
    var left: Double?
    var right: Double?
    var chargingCase: Double?
    var headphones: Double?
    var combined: Double?

    // Prefer the system's combined value, keeping the case out of the fallback.
    var listeningLevel: Double? { combined ?? [left, right].compactMap { $0 }.min() ?? headphones }
}

/// Optional, read-only getters in the installed IOBluetooth framework. These are
/// private APIs: check the complete ABI before calling and fail back to names.
/// No scanning, pairing, daemon changes or additional framework loading.
enum BluetoothArtworkMetadata {
    static func artwork(for device: IOBluetoothDevice) -> AirPodsArtwork? {
        AirPodsArtwork.resolve(name: device.name ?? "",
            vendorID: readUInt16(device, "vendorID"),
            productID: readUInt16(device, "productID"),
            colorID: readUInt8(device, "colorID"))
    }

    static func battery(for device: IOBluetoothDevice) -> AirPodsBatteryDetails {
        func level(_ selector: String) -> Double? {
            guard let percent = readUInt8(device, selector), (0...100).contains(percent) else { return nil }
            return Double(percent) / 100
        }
        return .init(left: level("batteryPercentLeft"), right: level("batteryPercentRight"),
                     chargingCase: level("batteryPercentCase"),
                     headphones: level("batteryPercentSingle"), combined: level("batteryPercentCombined"))
    }

    private static func getter(_ object: NSObject, _ name: String, returning type: String) -> (Selector, IMP)? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector), let cls = object_getClass(object),
              let method = class_getInstanceMethod(cls, selector),
              method_getNumberOfArguments(method) == 2 else { return nil }
        let result = method_copyReturnType(method)
        defer { free(result) }
        guard String(cString: result) == type else { return nil }
        return (selector, method_getImplementation(method))
    }
    private static func readUInt16(_ object: NSObject, _ name: String) -> Int? {
        guard let (selector, implementation) = getter(object, name, returning: "S") else { return nil }
        typealias Function = @convention(c) (AnyObject, Selector) -> UInt16
        return Int(unsafeBitCast(implementation, to: Function.self)(object, selector))
    }
    private static func readUInt8(_ object: NSObject, _ name: String) -> Int? {
        guard let (selector, implementation) = getter(object, name, returning: "C") else { return nil }
        typealias Function = @convention(c) (AnyObject, Selector) -> UInt8
        return Int(unsafeBitCast(implementation, to: Function.self)(object, selector))
    }
}
