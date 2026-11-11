import XCTest
@testable import NotchCore

final class MotionValueTests: XCTestCase {
    func testInterruptedSpringRetainsVelocityAndSettlesWithoutFrameRateDrift() {
        var a = MotionValue(208); a.target = 400
        a.advance(seconds: 0.075)
        let speed = a.velocity, position = a.value
        a.target = 208
        XCTAssertEqual(a.velocity, speed); XCTAssertEqual(a.value, position)
        for _ in 0..<120 { a.advance(seconds: 1.0/120) }
        XCTAssertTrue(a.settled)
        var low = MotionValue(208); low.target = 400
        var high = low
        for _ in 0..<30 { low.advance(seconds: 1.0/30) }
        for _ in 0..<120 { high.advance(seconds: 1.0/120) }
        XCTAssertEqual(low.value, high.value, accuracy: 1e-8)
        XCTAssertEqual(low.velocity, high.velocity, accuracy: 1e-8)
    }
}
