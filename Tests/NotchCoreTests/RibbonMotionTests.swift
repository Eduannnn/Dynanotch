import XCTest
@testable import NotchCore

final class RibbonMotionTests: XCTestCase {
    func testPausesAtBothReadingPositionsAndNeverReverses() {
        // 300pt text in 180pt viewport: four seconds to read the end.
        XCTAssertEqual(RibbonFrame.at(elapsed: 1, textWidth: 300, viewportWidth: 180).offset, 0)
        XCTAssertEqual(RibbonFrame.at(elapsed: 3.5, textWidth: 300, viewportWidth: 180).offset, -60)
        XCTAssertEqual(RibbonFrame.at(elapsed: 6, textWidth: 300, viewportWidth: 180).offset, -120)
        XCTAssertLessThan(RibbonFrame.at(elapsed: 8, textWidth: 300, viewportWidth: 180).offset, -120)
    }
    func testLoopBoundaryMatchesSecondCopyWithoutVisibleJump() {
        let width = 336.0
        let duration = 3.0 + width / 30
        let before = RibbonFrame.at(elapsed: duration - 0.00001, textWidth: 300, viewportWidth: 180)
        let after = RibbonFrame.at(elapsed: duration + 0.00001, textWidth: 300, viewportWidth: 180)
        XCTAssertEqual(before.offset + width, after.offset, accuracy: 0.001)
        XCTAssertFalse(after.fadedEdges)
    }
    func testFadeClearsWhileRestingAndFittingTextStaysStill() {
        XCTAssertFalse(RibbonFrame.at(elapsed: 0.5, textWidth: 300, viewportWidth: 180).fadedEdges)
        XCTAssertTrue(RibbonFrame.at(elapsed: 3, textWidth: 300, viewportWidth: 180).fadedEdges)
        XCTAssertFalse(RibbonFrame.at(elapsed: 6, textWidth: 300, viewportWidth: 180).fadedEdges)
        XCTAssertEqual(RibbonFrame.at(elapsed: 100, textWidth: 150, viewportWidth: 180).offset, 0)
    }
}
