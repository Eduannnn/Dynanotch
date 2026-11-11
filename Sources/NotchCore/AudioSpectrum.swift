import Foundation

/// Six broad musical bands, measured from PCM. No time-based or decorative signal.
public struct AudioSpectrum {
    public static let centers: [Double] = [80, 200, 500, 1250, 3000, 7500]
    private struct Band {
        let b0: Double, b2: Double, a1: Double, a2: Double
        var z1 = 0.0, z2 = 0.0
        init(frequency: Double, sampleRate: Double) {
            let w = 2*Double.pi*min(frequency, sampleRate*0.44)/sampleRate
            let alpha = sin(w)/(2*1.0), a0 = 1+alpha
            b0 = alpha/a0; b2 = -alpha/a0; a1 = -2*cos(w)/a0; a2 = (1-alpha)/a0
        }
        mutating func process(_ x: Double) -> Double {
            let y = b0*x+z1
            z1 = z2-a1*y; z2 = b2*x-a2*y
            return y
        }
    }
    private var filters: [Band]
    private let sampleRate: Double
    // One reference for all bands: retain spectral contrast while adapting to
    // different recordings. Slow release lets beats fall away from recent peaks.
    private var referencePeak = 0.05
    public init(sampleRate: Double) {
        let rate = sampleRate.isFinite && sampleRate >= 8000 ? sampleRate : 48_000
        self.sampleRate = rate
        filters = (0..<2).flatMap { _ in Self.centers.map { Band(frequency: $0, sampleRate: rate) } }
    }
    public mutating func analyze(frameCount: Int, channels: Int, sample: (Int, Int) -> Float) -> [Double] {
        let n = min(8192, max(0, frameCount)), count = min(2, max(0, channels))
        guard n > 0, count > 0 else { return Array(repeating: 0, count: 6) }
        var energy = Array(repeating: 0.0, count: 6)
        for frame in 0..<n {
            for channel in 0..<count {
                let raw = Double(sample(frame, channel)), x = raw.isFinite ? max(-4, min(4, raw)) : 0
                for band in 0..<6 {
                    let y = filters[channel*6+band].process(x)
                    energy[band] += y*y
                }
            }
        }
        let rms = energy.map { sqrt(max(0, $0 / Double(n * count))) }
        let peak = rms.max() ?? 0
        referencePeak = max(peak, referencePeak * exp(-Double(n) / sampleRate / 3.0))
        guard peak > 0.00001 else { return Array(repeating: 0, count: 6) }
        let reference = max(0.025, referencePeak * 1.25)
        return rms.map { band in
            // Unlike the former dB scale, amplitude changes retain visible motion.
            // The shared reference prevents every frequency normalizing to full height.
            0.94 * pow(min(1, max(0, band - 0.00001) / reference), 0.7)
        }
    }
}
