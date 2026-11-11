import Foundation

/// Pick a substantial chromatic region rather than a frequent white/gray pixel bin.
public enum ArtworkPalette {
    public static func colors(from pixels: [RGB]) -> (RGB, RGB) {
        struct Group {
            var r = 0.0, g = 0.0, b = 0.0, weight = 0.0
            var count = 0
            var color: RGB { RGB(r / weight, g / weight, b / weight).readable }
        }
        var groups: [Int: Group] = [:]
        var neutral = Group()
        for pixel in pixels {
            let high = max(pixel.r, pixel.g, pixel.b), low = min(pixel.r, pixel.g, pixel.b)
            guard high > 0.06 else { continue }
            neutral.r += pixel.r; neutral.g += pixel.g; neutral.b += pixel.b
            neutral.weight += 1; neutral.count += 1
            let chroma = high - low, saturation = chroma / high
            guard saturation >= 0.25, high >= 0.12 else { continue }
            var hue: Double
            if high == pixel.r { hue = (pixel.g - pixel.b) / chroma }
            else if high == pixel.g { hue = (pixel.b - pixel.r) / chroma + 2 }
            else { hue = (pixel.r - pixel.g) / chroma + 4 }
            hue = (hue / 6 + 1).truncatingRemainder(dividingBy: 1)
            let key = Int(floor(hue * 12 + 0.5)) % 12
            let weight = (0.35 + 0.65 * saturation) * (0.35 + 0.65 * high)
            var group = groups[key] ?? Group()
            group.r += pixel.r * weight; group.g += pixel.g * weight; group.b += pixel.b * weight
            group.weight += weight; group.count += 1; groups[key] = group
        }
        // A lone colorful compression pixel must not recolor monochrome artwork.
        let minimum = max(3, Int(ceil(Double(pixels.count) * 0.01)))
        let ranked = groups.filter { $0.value.count >= minimum }.sorted {
            $0.value.weight == $1.value.weight ? $0.key < $1.key : $0.value.weight > $1.value.weight
        }
        guard let first = ranked.first else {
            let gray = neutral.weight > 0 ? neutral.color : RGB(0.72, 0.72, 0.72)
            return (gray, gray)
        }
        let primary = first.value.color
        return (primary, ranked.dropFirst().first?.value.color ?? primary)
    }
}
