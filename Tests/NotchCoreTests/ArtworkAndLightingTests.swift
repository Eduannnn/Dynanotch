import XCTest
import CoreGraphics
@testable import NotchCore

final class ArtworkAndLightingTests: XCTestCase {
    func testPaleBackgroundDoesNotDrownOutCoverColor() {
        let pixels = Array(repeating: RGB(0.95, 0.93, 0.94), count: 400)
            + Array(repeating: RGB(0.32, 0.12, 0.62), count: 100)
        let color = ArtworkPalette.colors(from: pixels).0
        XCTAssertGreaterThan(color.b - color.g, 0.3)
        XCTAssertGreaterThan(color.r - color.g, 0.1)
    }
    func testYellowCoverOutweighsSmallBlueRegion() {
        let pixels = Array(repeating: RGB(0.96, 0.91, 0.08), count: 220)
            + Array(repeating: RGB(0.06, 0.12, 0.48), count: 70)
            + Array(repeating: RGB(0.03, 0.03, 0.03), count: 300)
        let color = ArtworkPalette.colors(from: pixels).0
        XCTAssertGreaterThan(color.r, 0.8); XCTAssertGreaterThan(color.g, 0.8)
        XCTAssertLessThan(color.b, 0.2)
    }
    func testBlueAndBlackCannotInventPurple() {
        let pixels = Array(repeating: RGB(0.03, 0.03, 0.03), count: 400)
            + Array(repeating: RGB(0.04, 0.42, 0.92), count: 160)
        let color = ArtworkPalette.colors(from: pixels).0
        XCTAssertGreaterThan(color.b, color.g); XCTAssertGreaterThan(color.g, color.r)
    }
    func testMonochromeIgnoresIsolatedColorNoise() {
        let pixels = Array(repeating: RGB(0.6, 0.6, 0.6), count: 500) + [RGB(1, 0, 1)]
        let color = ArtworkPalette.colors(from: pixels).0
        XCTAssertEqual(color.r, color.g, accuracy: 0.005)
        XCTAssertEqual(color.g, color.b, accuracy: 0.005)
    }
    func testProximityRespondsOutsideActualBodyAndFadesAtDistance() {
        let frame = CGRect(x: 100, y: 100, width: 284, height: 39.5)
        let near = EdgeLighting.response(to: CGPoint(x: 210, y: 60), around: frame)
        XCTAssertFalse(frame.contains(CGPoint(x: 210, y: 60)))
        XCTAssertEqual(near.strength, 0.6, accuracy: 0.001)
        XCTAssertEqual(near.point.y, 1)
        XCTAssertEqual(EdgeLighting.response(to: CGPoint(x: 210, y: -10), around: frame).strength, 0)
        let left = EdgeLighting.response(to: CGPoint(x: 80, y: 120), around: frame)
        let right = EdgeLighting.response(to: CGPoint(x: 400, y: 120), around: frame)
        XCTAssertEqual(left.point.x, 0); XCTAssertEqual(right.point.x, 1)
        XCTAssertGreaterThan(left.strength, 0); XCTAssertGreaterThan(right.strength, 0)
    }
}
