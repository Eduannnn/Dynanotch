import XCTest
@testable import NotchCore

final class MusicFavoriteActionTests: XCTestCase {
    func testRejectsMissingAndUnsafeTrackIdentity() {
        for id in ["", "stream", "1234", "\"\nend tell\n", "0123456789ABCDEG"] {
            XCTAssertNil(MusicFavoriteAction.script(trackID: id, favorited: true))
        }
    }
    func testTargetIsGuardedAndActionStaysInsideMusic() {
        let script = MusicFavoriteAction.script(trackID: "0123456789ABCDEF", favorited: true)!
        let guardRange = script.range(of: "then error")!
        let writeRange = script.range(of: "set favorited of t to true")!
        XCTAssertLessThan(guardRange.lowerBound, writeRange.lowerBound)
        XCTAssertTrue(script.contains("application id \"com.apple.Music\""))
        XCTAssertTrue(script.contains("return favorited of t as text"))
        XCTAssertTrue(MusicFavoriteAction.script(trackID: "0123456789ABCDEF", favorited: false)!.contains("set favorited of t to false"))
    }
}
