import AppKit

/// Gives the notch a place in the compositor outside the animated desktop stack.
/// SkyLight is private, so the regular AppKit panel remains the fallback.
@MainActor final class NotchOverlaySpace {
    private typealias Connection = @convention(c) () -> Int32
    private typealias Create = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias Destroy = @convention(c) (Int32, UInt64) -> Void
    private typealias SetLevel = @convention(c) (Int32, UInt64, Int32) -> Void
    private typealias GetLevel = @convention(c) (Int32, UInt64) -> Int32
    private typealias Visibility = @convention(c) (Int32, CFArray) -> Void
    private typealias AddWindows = @convention(c) (Int32, CFArray, CFArray) -> Void

    private let connection: Int32
    private let create: Create
    private let destroy: Destroy
    private let setLevel: SetLevel
    private let getLevel: GetLevel
    private let show: Visibility
    private let hide: Visibility
    private let addWindows: AddWindows
    private var space: UInt64?
    private var unavailable = false

    init?() {
        // AppKit already loads SkyLight into this process.
        let symbols = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let address = dlsym(symbols, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        guard let connection = load("CGSMainConnectionID", as: Connection.self),
              let create = load("CGSSpaceCreate", as: Create.self),
              let destroy = load("CGSSpaceDestroy", as: Destroy.self),
              let setLevel = load("CGSSpaceSetAbsoluteLevel", as: SetLevel.self),
              let getLevel = load("SLSSpaceGetAbsoluteLevel", as: GetLevel.self),
              let show = load("CGSShowSpaces", as: Visibility.self),
              let hide = load("CGSHideSpaces", as: Visibility.self),
              let addWindows = load("CGSAddWindowsToSpaces", as: AddWindows.self) else { return nil }
        self.connection = connection()
        self.create = create
        self.destroy = destroy
        self.setLevel = setLevel
        self.getLevel = getLevel
        self.show = show
        self.hide = hide
        self.addWindows = addWindows
    }

    func attach(_ window: NSWindow) -> Bool {
        guard !unavailable, window.windowNumber > 0 else { return false }
        if space == nil {
            let id = create(connection, 1, nil)
            guard id != 0 else { unavailable = true; return false }
            let level: Int32 = 400
            setLevel(connection, id, level)
            guard getLevel(connection, id) == level else {
                destroy(connection, id)
                unavailable = true
                return false
            }
            show(connection, [NSNumber(value: id)] as CFArray)
            space = id
        }
        guard let space else { return false }
        addWindows(connection, [NSNumber(value: window.windowNumber)] as CFArray,
                   [NSNumber(value: space)] as CFArray)
        return true
    }

    func detach() {
        guard let space else { return }
        hide(connection, [NSNumber(value: space)] as CFArray)
        destroy(connection, space)
        self.space = nil
    }
}
