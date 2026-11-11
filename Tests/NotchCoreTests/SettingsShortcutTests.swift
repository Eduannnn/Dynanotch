import XCTest
@testable import NotchCore

final class SettingsShortcutTests: XCTestCase {
    func testCommandCommaOnlyWorksOverNotch() {
        XCTAssertTrue(isNotchSettingsShortcut(characters: ",", command: true, shift: false, option: false, control: false, overNotch: true))
        XCTAssertFalse(isNotchSettingsShortcut(characters: ",", command: true, shift: false, option: false, control: false, overNotch: false))
    }
    func testTypingAndOtherCommandShortcutsPassThrough() {
        XCTAssertFalse(isNotchSettingsShortcut(characters: ",", command: false, shift: false, option: false, control: false, overNotch: true))
        XCTAssertFalse(isNotchSettingsShortcut(characters: "q", command: true, shift: false, option: false, control: false, overNotch: true))
        XCTAssertFalse(isNotchSettingsShortcut(characters: ",", command: true, shift: false, option: true, control: false, overNotch: true))
        XCTAssertFalse(isNotchSettingsShortcut(characters: ",", command: true, shift: true, option: false, control: false, overNotch: true))
    }
}
