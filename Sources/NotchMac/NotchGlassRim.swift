import SwiftUI

/// An open outline reaches the screen at both ends without a horizontal top stroke.
struct NotchGlassRim: View {
    var radius: CGFloat
    var ear: CGFloat
    var highlight: CGPoint
    var strength: Double = 0
    var staticPreview: Bool = false

    var body: some View {
        SpecularGlassRim(surface: NotchSilhouette(radius: radius, ear: ear),
                         edge: NotchSilhouette(radius: radius, ear: ear, closesTop: false),
                         highlight: highlight, strength: strength, staticPreview: staticPreview)
    }
}

/// Shared edge material for the notch and its separate circular status bubble.
struct SpecularGlassRim<Surface: Shape, Edge: Shape>: View {
    var surface: Surface
    var edge: Edge
    var highlight: CGPoint
    var strength: Double = 0
    var staticPreview: Bool = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            edge.stroke(contrast == .increased ? Color(white: 0.4) : Color(red: 0.14, green: 0.14, blue: 0.16), lineWidth: 0.8)
            if #available(macOS 26.0, *), !reduceTransparency, !staticPreview {
                // Sample the surrounding backdrop with system glass and expose only its edge.
                Color.clear
                    .glassEffect(.regular, in: surface)
                    .mask(edge.stroke(lineWidth: 1.4))
                    .opacity(0.30)
            }
            GeometryReader { proxy in
                let center = UnitPoint(x: highlight.x, y: highlight.y)
                let reach = max(20, min(140, proxy.size.width * 0.4))
                edge.stroke(RadialGradient(colors: [.white.opacity(0.27), .white.opacity(0.07), .clear],
                    center: center, startRadius: 0, endRadius: reach), lineWidth: 0.8)
                    .opacity(strength * 0.58)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: highlight)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: strength)
            }
        }
            .opacity(contrast == .increased ? 1 : 0.8)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
