import XCTest
@testable import NotchCore

final class NotchCoreTests: XCTestCase {
    func testSeekScriptChecksTrackBeforeWritingPosition() throws {
        let music = try XCTUnwrap(MediaSeekAction.script(bundleID: "com.apple.Music", trackID: "AABBCC1122334455", position: 34.5))
        let guardRange = try XCTUnwrap(music.range(of: #"if (persistent ID of current track as text) is not "AABBCC1122334455""#))
        let writeRange = try XCTUnwrap(music.range(of: "set player position to 34.5"))
        XCTAssertLessThan(guardRange.lowerBound, writeRange.lowerBound)
        XCTAssertTrue(music.contains("with timeout of 3 seconds"))

        let spotify = try XCTUnwrap(MediaSeekAction.script(bundleID: "com.spotify.client", trackID: #"spotify:local:a"b\c"#, position: 0))
        XCTAssertTrue(spotify.contains(#"(id of current track as text) is not "spotify:local:a\"b\\c""#))
        XCTAssertNil(MediaSeekAction.script(bundleID: "com.apple.Music", trackID: "", position: 1))
        XCTAssertNil(MediaSeekAction.script(bundleID: "com.apple.Music", trackID: "a\nb", position: 1))
        XCTAssertNil(MediaSeekAction.script(bundleID: "other", trackID: "track", position: 1))
        XCTAssertNil(MediaSeekAction.script(bundleID: "com.apple.Music", trackID: "track", position: .nan))
    }

    func testNoticeQueueDeduplicatesAndUpdatesLateBattery() {
        var queue = NoticeQueue()
        XCTAssertTrue(queue.enqueue(.init(key: "pods", name: "AirPods", kind: .earbuds)))
        XCTAssertFalse(queue.enqueue(.init(key: "pods", name: "AirPods", kind: .earbuds, battery: 0.72)))
        XCTAssertEqual(queue.current?.battery, 0.72)
        queue.enqueue(.init(key: "pods", name: "AirPods", kind: .earbuds, connected: false, battery: 0.72))
        queue.advance()
        XCTAssertEqual(queue.current?.connected, false)
        XCTAssertNil(queue.current?.battery)
    }
    func testQueueBoundAndDismiss() {
        var queue = NoticeQueue()
        for i in 0..<12 { queue.enqueue(.init(key: "\(i)", name: "Device", kind: .usb)) }
        XCTAssertEqual(queue.pending.count, 8)
        XCTAssertEqual(queue.pending.first?.key, "4")
        queue.dismiss(key: "0")
        XCTAssertEqual(queue.current?.key, "4")
        queue.dismiss(key: "8")
        XCTAssertFalse(queue.pending.contains { $0.key == "8" })
    }
    func testPresentationPriorityAndScrubbingLatch() {
        XCTAssertEqual(Presentation.resolve(osd: true, notice: true, media: true, hovered: true, scrubbing: true, peek: true), .osd)
        XCTAssertEqual(Presentation.resolve(osd: false, notice: false, media: true, hovered: false, scrubbing: true, peek: false), .expanded)
    }
    func testNoticeAndIdlePresentationWithoutControlCenter() {
        XCTAssertEqual(Presentation.resolve(osd: false, notice: true, media: true, hovered: true, scrubbing: false, peek: true), .notice)
        XCTAssertEqual(Presentation.resolve(osd: false, notice: false, media: false, hovered: true, scrubbing: false, peek: false), .idle)
    }
    func testAirPodsArtworkFamiliesAndUnrelatedHeadphones() {
        XCTAssertEqual(AirPodsFamily.matching(name: "Eduan’s AirPods Pro"), .airpodsPro)
        XCTAssertEqual(AirPodsFamily.matching(name: "AirPods Max"), .airpodsMax)
        XCTAssertEqual(AirPodsFamily.matching(name: "AirPod Max"), .airpodsMax)
        XCTAssertEqual(AirPodsFamily.matching(name: "AIRPODS (2nd generation)"), .airpods)
        XCTAssertNil(AirPodsFamily.matching(name: "Bose Headphones"))
        XCTAssertNil(AirPodsFamily.matching(name: "Galaxy Buds"))
    }
    func testHardwareAirPodsModelWinsOverRenamedDevice() {
        let max = AirPodsArtwork.resolve(name: "My headphones", vendorID: 76, productID: 8202, colorID: 3)
        XCTAssertEqual(max?.family, .airpodsMax)
        XCTAssertEqual(max?.productID, 8202)
        XCTAssertEqual(max?.colorID, 3)
        XCTAssertEqual(AirPodsArtwork.resolve(name: "AirPods", vendorID: 76, productID: 8228, colorID: 0)?.family, .airpodsPro)
        XCTAssertNil(AirPodsArtwork.resolve(name: "AirPods Max", vendorID: 1234, productID: 8202, colorID: 3))
    }
    func testMissingHardwareMetadataUsesOnlyFamilyFallback() {
        let fallback = AirPodsArtwork.resolve(name: "My AirPods Max", vendorID: nil, productID: 8223, colorID: 22)
        XCTAssertEqual(fallback?.productID, 8202)
        XCTAssertNil(fallback?.colorID)
        XCTAssertNil(AirPodsArtwork.resolve(name: "Headphones", vendorID: nil, productID: nil, colorID: nil))
    }
    func testAirPodsColorCandidatesAndFallbackOrder() {
        let blue = AirPodsArtwork(family: .airpodsMax, productID: 8202, colorID: 3)
        XCTAssertEqual(blue.movieRelativePaths.first, "Banner-PID-8202-mov/Banner-PID-8202-3-Loop.mov")
        XCTAssertTrue(AirPodsArtwork(family: .airpodsMax, colorID: 0).movieRelativePaths[0].contains("-15-Loop"))
        let purple = AirPodsArtwork(family: .airpodsMax, productID: 8223, colorID: 22)
        XCTAssertTrue(purple.movieRelativePaths[0].contains("8223-22-Loop"))
        XCTAssertTrue(purple.movieRelativePaths[1].contains("8223-default-Loop"))
        XCTAssertFalse(purple.movieRelativePaths.contains { $0.contains("8202-22") })
        XCTAssertNil(AirPodsArtwork(family: .airpodsMax, colorID: -1).colorID)
    }
    func testVisibleNoticeReceivesLateColorMetadata() {
        var queue = NoticeQueue()
        queue.enqueue(.init(key: "headphones", name: "Headphones", kind: .headphones))
        let artwork = AirPodsArtwork(family: .airpodsMax, colorID: 17)
        queue.updateArtwork(key: "headphones", artwork: artwork)
        XCTAssertEqual(queue.current?.airPodsArtwork, artwork)
        XCTAssertTrue(queue.pending.isEmpty)
    }
    func testSeekClampsWithoutSkippingTrack() {
        XCTAssertEqual(seekPosition(fraction: 1.1, duration: 200), 199.99)
        XCTAssertEqual(seekPosition(fraction: -0.2, duration: 200), 0)
        XCTAssertEqual(seekPosition(fraction: 0.5, duration: 200), 100)
        XCTAssertNil(seekPosition(fraction: .nan, duration: 200))
        XCTAssertNil(seekPosition(fraction: 0.5, duration: 0))
    }
    func testTrackIdentityIgnoresPartialMetadataForStableID() {
        let a = TrackIdentity(source: "Music", identifier: "123", title: "Song")
        let b = TrackIdentity(source: "Music", identifier: "123", title: "Song", artist: "Artist")
        XCTAssertTrue(a.isSameTrack(as: b))
        XCTAssertFalse(a.isSameTrack(as: .init(source: "Spotify", identifier: "123", title: "Song")))
        XCTAssertFalse(a.isSameTrack(as: .init(source: "Music", identifier: "456", title: "Song")))
    }
    func testDarkArtworkIsReadableWithoutLosingHue() {
        let red = RGB(0.15, 0.01, 0.01).readable
        XCTAssertGreaterThanOrEqual(red.luminance, 0.22)
        XCTAssertGreaterThan(red.r, red.g)
        XCTAssertGreaterThanOrEqual(RGB(0, 0, 0.1).readable.luminance, 0.22)
        XCTAssertGreaterThanOrEqual(RGB(0, 0, 0).readable.luminance, 0.22)
    }
    func testInvalidBatteryIsNeverDisplayedAsRealValue() {
        XCTAssertNil(DeviceNotice(key: "x", name: "USB", kind: .usb, battery: .nan).battery)
        XCTAssertNil(DeviceNotice(key: "x", name: "USB", kind: .usb, battery: 12).battery)
        XCTAssertEqual(clockText(.infinity), "0:00")
        XCTAssertEqual(clockText(125), "2:05")
    }
}
