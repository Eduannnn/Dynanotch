import XCTest
@testable import NotchCore

final class CountdownTests: XCTestCase {
    func testPauseResumeAndRelaunchKeepActualRemainingTime() throws {
        let t = Date(timeIntervalSince1970: 10_000)
        var timer = Countdown()
        XCTAssertTrue(timer.start(seconds: 90, at: t))
        XCTAssertEqual(timer.remaining(at: t.addingTimeInterval(25)), 65)
        timer.pause(remaining: 65)
        XCTAssertEqual(timer.remaining(at: t.addingTimeInterval(200)), 65)
        timer.resume(at: t.addingTimeInterval(200))
        let restored = try JSONDecoder().decode(Countdown.self, from: JSONEncoder().encode(timer))
        XCTAssertEqual(restored.remaining(at: t.addingTimeInterval(230)), 35)
        XCTAssertEqual(restored.remaining(at: t.addingTimeInterval(300)), 0)
    }
    func testCompletionRepeatCancellationAndInvalidInput() {
        var timer = Countdown(); let now = Date()
        XCTAssertFalse(timer.start(seconds: .nan, at: now))
        XCTAssertFalse(timer.start(seconds: -10, at: now))
        XCTAssertFalse(timer.start(seconds: 86_401, at: now))
        XCTAssertTrue(timer.start(seconds: 30, at: now))
        timer.finish(); XCTAssertEqual(timer.phase, .finished)
        timer.restart(at: now); XCTAssertEqual(timer.remaining(at: now), 30)
        timer.cancel(); XCTAssertFalse(timer.exists)
    }
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
