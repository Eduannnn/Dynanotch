import AppKit
import SwiftUI
import NotchCore

/// One persistent cover, with a face change at the edge of the turn. Rapid updates coalesce.
struct FlippingArtworkView: View {
    var image: NSImage?
    var identity: TrackIdentity?
    var size: CGFloat
    var radius: CGFloat
    var onPhase: ((String) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedImage: NSImage?
    @State private var displayedIdentity: TrackIdentity?
    @State private var pendingImage: NSImage?
    @State private var pendingIdentity: TrackIdentity?
    @State private var angle = 0.0
    @State private var turning = false
    @State private var turnTask: Task<Void, Never>?

    init(image: NSImage?, identity: TrackIdentity?, size: CGFloat, radius: CGFloat, onPhase: ((String) -> Void)? = nil) {
        self.image = image; self.identity = identity; self.size = size
        self.radius = radius
        self.onPhase = onPhase
        _displayedImage = State(initialValue: image)
        _displayedIdentity = State(initialValue: identity)
    }
    var body: some View {
        ArtworkView(image: displayedImage, size: size, radius: radius)
            .overlay {
                ArtworkFlipGlass(angle: angle, radius: radius)
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
            .onChange(of: identity) { _, _ in receive() }
            .onChange(of: image.map(ObjectIdentifier.init)) { _, _ in receive() }
            .onChange(of: reduceMotion) { _, value in if value { settle() } }
            .onDisappear { turnTask?.cancel() }
    }
    private func receive() {
        // Metadata arrives immediately; keep the outgoing cover until the new
        // image is available, then perform the normal flip with the right face.
        if identity != nil && image == nil { return }
        if let identity, let current = displayedIdentity, current.isSameTrack(as: identity), !turning {
            displayedImage = image; displayedIdentity = identity; return
        }
        pendingIdentity = identity; pendingImage = image
        guard !reduceMotion, displayedIdentity != nil, identity != nil else { settle(); return }
        if !turning { turn() }
    }
    private func turn() {
        turning = true
        onPhase?("outgoing")
        turnTask?.cancel()
        withAnimation(.easeIn(duration: 0.16)) { angle = -90 }
        turnTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) {
                    displayedImage = pendingImage; displayedIdentity = pendingIdentity
                    pendingIdentity = nil; pendingImage = nil; angle = 90
                }
                onPhase?("incoming")
                // Give the new face one frame at its edge before returning it toward the viewer.
                try await Task.sleep(for: .milliseconds(16))
                withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) { angle = 0 }
                try await Task.sleep(for: .milliseconds(330))
                turning = false
                onPhase?("idle")
                if let pending = pendingIdentity, let current = displayedIdentity, pending.isSameTrack(as: current) {
                    displayedImage = pendingImage; pendingImage = nil; pendingIdentity = nil
                } else if pendingIdentity != nil { turn() }
            } catch { }
        }
    }
    private func settle() {
        turnTask?.cancel(); turnTask = nil; turning = false
        onPhase?("idle")
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedImage = image; displayedIdentity = identity
            pendingImage = nil; pendingIdentity = nil; angle = 0
        }
    }
}

private struct ArtworkFlipGlass: View, Animatable {
    var angle: Double
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let strength = sin(unit(abs(angle) / 90) * .pi * 0.8)
        let sweep = 0.5 + angle / 200
        ZStack {
            if #available(macOS 26.0, *), !reduceTransparency, strength > 0.01 {
                Color.clear
                    .glassEffect(.clear, in: shape)
                    .opacity(0.32)
            }
            shape.fill(LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.16), location: 0.39),
                    .init(color: .white.opacity(0.48), location: 0.50),
                    .init(color: .white.opacity(0.10), location: 0.63),
                    .init(color: .clear, location: 1),
                ],
                startPoint: UnitPoint(x: sweep - 0.35, y: 0.15),
                endPoint: UnitPoint(x: sweep + 0.35, y: 0.85)
            ))
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.66), .clear, .white.opacity(0.22)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.75
            )
        }
        .clipShape(shape)
        .opacity(strength)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
