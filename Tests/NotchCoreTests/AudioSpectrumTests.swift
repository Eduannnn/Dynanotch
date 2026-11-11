import XCTest
@testable import NotchCore

final class AudioSpectrumTests: XCTestCase {
    func testStrongAndWeakFrequenciesKeepDistinctHeights() {
        var analyzer = AudioSpectrum(sampleRate: 48_000)
        let levels = analyzer.analyze(frameCount: 8192, channels: 1) { frame, _ in
            let time = Double(frame) / 48_000
            return Float(0.2 * sin(2 * Double.pi * 200 * time) + 0.025 * sin(2 * Double.pi * 3000 * time))
        }
        XCTAssertGreaterThan(levels[1] - levels[4], 0.2, "Weaker frequencies should not crowd the strongest bar.")
        XCTAssertGreaterThan(levels[4], 0.04, "The quieter frequency must still remain visible.")
        XCTAssertLessThan(levels.max()!, 0.9, "Ordinary loud audio must leave headroom.")
    }
    func testQuietAudioRemainsVisibleWithGentlerLoudResponse() {
        let levels = [0.003, 0.03, 0.3].map { amplitude in
            var analyzer = AudioSpectrum(sampleRate: 48_000)
            return analyzer.analyze(frameCount: 8192, channels: 1) { frame, _ in
                Float(amplitude * sin(2 * Double.pi * 1250 * Double(frame) / 48_000))
            }[3]
        }
        XCTAssertGreaterThan(levels[0], 0.08, "Quiet audio must still move a bar.")
        XCTAssertLessThan(levels[0], levels[1])
        XCTAssertLessThan(levels[1], levels[2])
        XCTAssertLessThan(levels[2], 0.85, "Strong audio should leave visual headroom.")
    }
    func testBeatEnvelopeHasVisibleContrastWithoutAllBarsMaxingOut() {
        var analyzer = AudioSpectrum(sampleRate: 48_000)
        var cursor = 0
        func block(_ amplitude: Double) -> [Double] {
            defer { cursor += 1024 }
            return analyzer.analyze(frameCount: 1024, channels: 1) { frame, _ in
                let t = Double(cursor + frame) / 48_000
                return Float(amplitude * sin(2 * .pi * 500 * t))
            }
        }
        var loud = [Double]()
        for _ in 0..<20 { loud = block(0.2) }
        var soft = [Double]()
        for _ in 0..<10 { soft = block(0.02) }
        XCTAssertGreaterThan(loud[2] - soft[2], 0.4, "A beat falling 20 dB must produce a visible fall.")
        XCTAssertGreaterThan(soft[2], 0.05, "Quiet passages must still move.")
        XCTAssertLessThan(loud.max()!, 0.9)
        XCTAssertGreaterThan(loud[2] - loud[5], 0.3)
    }

    func testSilenceAndNonfiniteSamplesStaySilent() {
        var analyzer = AudioSpectrum(sampleRate: 48_000)
        XCTAssertEqual(analyzer.analyze(frameCount: 2048, channels: 2) { _,_ in 0 }, Array(repeating: 0, count: 6))
        XCTAssertEqual(analyzer.analyze(frameCount: 2048, channels: 2) { _,_ in .nan }, Array(repeating: 0, count: 6))
    }
    func testEachMusicalBandRespondsToItsActualFrequency() {
        for (index, frequency) in AudioSpectrum.centers.enumerated() {
            var analyzer = AudioSpectrum(sampleRate: 48_000)
            let bands = analyzer.analyze(frameCount: 8192, channels: 1) { frame,_ in
                Float(0.2*sin(2*Double.pi*frequency*Double(frame)/48_000))
            }
            XCTAssertEqual(bands.firstIndex(of: bands.max()!), index)
            XCTAssertGreaterThan(bands[index], 0.4)
        }
    }
    func testRightChannelAndOppositePhaseStereoAreNotDiscarded() {
        var left = AudioSpectrum(sampleRate: 48_000), right = left, opposite = left
        func tone(_ frame: Int) -> Float { Float(0.1*sin(2*Double.pi*500*Double(frame)/48_000)) }
        let l = left.analyze(frameCount: 4096, channels: 2) { f,c in c == 0 ? tone(f) : 0 }
        let r = right.analyze(frameCount: 4096, channels: 2) { f,c in c == 1 ? tone(f) : 0 }
        let p = opposite.analyze(frameCount: 4096, channels: 2) { f,c in c == 0 ? tone(f) : -tone(f) }
        XCTAssertEqual(l, r)
        XCTAssertGreaterThan(p[2], l[2])
    }
}
