import XCTest
@testable import NotchCore

final class HardwareMediaKeyTests: XCTestCase {
    private func stroke(_ key: HardwareMediaKey = .volumeUp, down: Bool = true, repeating: Bool = false) -> HardwareMediaKeyStroke {
        HardwareMediaKeyStroke.decode(subtype: 8, data1: (Int(key.rawValue) << 16) | ((down ? 0x0a : 0x0b) << 8) | (repeating ? 1 : 0))!
    }
    func testDecodesEverySupportedHardwareKeyAndRepeat() {
        for key: HardwareMediaKey in [.volumeUp, .volumeDown, .brightnessUp, .brightnessDown, .mute] {
            XCTAssertEqual(stroke(key).key, key)
            XCTAssertEqual(stroke(key, down: false).phase, .up)
        }
        XCTAssertTrue(stroke(repeating: true).isRepeat)
    }
    func testLeavesPlaybackBacklightAndUnrelatedSystemEventsAlone() {
        for key in [16, 17, 18, 21, 22, 99] {
            XCTAssertNil(HardwareMediaKeyStroke.decode(subtype: 8, data1: (key << 16) | 0x0a00))
        }
        XCTAssertNil(HardwareMediaKeyStroke.decode(subtype: 7, data1: 0x0a00))
        XCTAssertNil(HardwareMediaKeyStroke.decode(subtype: 8, data1: 0x0900))
    }
    func testFailedWritesAndDisabledTakeoverPassBothEdgesToMacOS() {
        var capture = MediaKeyCapture()
        XCTAssertFalse(capture.route(stroke(), eligible: true) { _ in false })
        XCTAssertFalse(capture.route(stroke(down: false), eligible: true) { _ in XCTFail("Never act on key up"); return true })
        XCTAssertFalse(capture.route(stroke(), eligible: false) { _ in XCTFail("Disabled takeover must not write"); return true })
    }
    func testHandledPressAndReleaseAreConsumedWithoutDoubleAdjustment() {
        var capture = MediaKeyCapture(), count = 0
        XCTAssertTrue(capture.route(stroke(), eligible: true) { _ in count += 1; return true })
        XCTAssertTrue(capture.route(stroke(repeating: true), eligible: true) { _ in count += 1; return true })
        XCTAssertTrue(capture.route(stroke(down: false), eligible: false) { _ in count += 1; return true })
        XCTAssertEqual(count, 2)
        XCTAssertFalse(capture.route(stroke(down: false), eligible: true) { _ in true })
    }
    func testCaptureResetRestoresOriginalKeyHandling() {
        var capture = MediaKeyCapture()
        XCTAssertTrue(capture.route(stroke(.mute), eligible: true) { _ in true })
        capture.reset()
        XCTAssertFalse(capture.route(stroke(.mute, down: false), eligible: true) { _ in true })
    }
    func testStandardAndFineStepsClampAtBothEnds() {
        XCTAssertEqual(hardwareLevelStep(0.5, increasing: true, fine: false), 0.5625)
        XCTAssertEqual(hardwareLevelStep(0.5, increasing: false, fine: true), 0.484375)
        XCTAssertEqual(hardwareLevelStep(0.99, increasing: true, fine: false), 1)
        XCTAssertEqual(hardwareLevelStep(0.01, increasing: false, fine: false), 0)
    }

    func testFourFineVolumeStepsReachZeroDespiteDeviceReadbackRounding() {
        var readback = hardwareVolumeStep(0, increasing: true, fine: false) + 0.002
        for expectedTick in [3, 2, 1, 0] {
            let target = hardwareVolumeStep(readback, increasing: false, fine: true)
            XCTAssertEqual(target, Double(expectedTick) / 64)
            readback = target + 0.002
        }
        XCTAssertEqual(hardwareVolumeStep(0, increasing: true, fine: true), 1.0 / 64)
        XCTAssertEqual(hardwareVolumeStep(0.05, increasing: false, fine: true), 3.0 / 64)
    }
}
