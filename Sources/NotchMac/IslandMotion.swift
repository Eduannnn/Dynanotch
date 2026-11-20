import AppKit
import SwiftUI

/// Public SwiftUI springs tuned for an island-style morph; no private animation ABI is called.
@MainActor enum IslandMotion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var shape: Animation {
        reduced ? .easeOut(duration: 0.1) : .spring(response: max(0.05, NotchThemeStore.shared.theme(state: "expanded").number("motion.response", 0.32)), dampingFraction: max(0.1, NotchThemeStore.shared.theme(state: "expanded").number("motion.damping", 0.88)), blendDuration: 0)
    }
    static var satellite: Animation {
        reduced ? .easeOut(duration: 0.1) : .spring(response: 0.46, dampingFraction: 0.90)
    }
    static var bubble: Animation {
        .spring(response: max(0.05, NotchThemeStore.shared.theme(state: "collapsed").number("motion.bubbleResponse", 0.57)), dampingFraction: max(0.1, NotchThemeStore.shared.theme(state: "collapsed").number("motion.bubbleDamping", 0.94)))
    }
    static var height: Animation {
        shape
    }
    static var fade: Animation { .easeOut(duration: reduced ? 0.08 : max(0.01, NotchThemeStore.shared.theme(state: "expanded").number("motion.fadeDuration", 0.14))) }
    static var content: AnyTransition {
        let effect = AnyTransition.modifier(active: IslandContentPhase(phase: 1, reduced: reduced), identity: IslandContentPhase(phase: 0, reduced: reduced))
        return .asymmetric(
            insertion: effect.animation(.easeOut(duration: 0.10)),
            removal: effect.animation(.easeOut(duration: 0.06))
        )
    }
}

private struct IslandContentPhase: AnimatableModifier {
    var phase: CGFloat
    var reduced: Bool
    var animatableData: CGFloat { get { phase } set { phase = newValue } }
    func body(content: Content) -> some View {
        content.opacity(1 - phase)

    }
}
