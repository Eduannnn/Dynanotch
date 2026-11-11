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
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.32), .clear, .black.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(min(1, abs(angle)/90))
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
