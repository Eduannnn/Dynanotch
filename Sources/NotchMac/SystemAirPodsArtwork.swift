import AppKit
import AVFoundation
import SwiftUI
import NotchCore

/// Paths only: Apple's pairing movies remain in the installed macOS bundle.
@MainActor enum SystemAirPodsArtwork {
    static let root = URL(fileURLWithPath: "/System/Library/CoreServices/BluetoothUIService.app/Contents/Resources", isDirectory: true)
    static let playbackWatchdog: TimeInterval = 8
    private static var posters: [URL: NSImage] = [:]

    static func url(for artwork: AirPodsArtwork) -> URL? {
        artwork.movieRelativePaths.lazy.map { root.appendingPathComponent($0) }
            .first { FileManager.default.isReadableFile(atPath: $0.path) }
    }
    static func url(for family: AirPodsFamily) -> URL? { url(for: AirPodsArtwork(family: family)) }
    static func cachedPoster(for artwork: AirPodsArtwork) -> NSImage? {
        url(for: artwork).flatMap { posters[$0] }
    }
    static func poster(for family: AirPodsFamily) async -> NSImage? { await poster(for: AirPodsArtwork(family: family)) }
    static func poster(for artwork: AirPodsArtwork) async -> NSImage? {
        guard let url = url(for: artwork) else { return nil }
        if let cached = posters[url] { return cached }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 168, height: 168)
        guard let image = try? await generator.image(at: CMTime(seconds: 0.7, preferredTimescale: 600)).image else { return nil }
        let result = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        posters[url] = result
        return result
    }
    static func preload() async {
        for family in AirPodsFamily.allCases { _ = await poster(for: family) }
    }
    static func diagnostic() async -> [[String: Any]] {
        var examples = AirPodsFamily.allCases.map { AirPodsArtwork(family: $0) }
        examples += [0, 2, 3, 15, 16, 17, 254].map { AirPodsArtwork(family: .airpodsMax, productID: 8202, colorID: $0) }
        examples += [18, 19, 20, 21, 22].map { AirPodsArtwork(family: .airpodsMax, productID: 8223, colorID: $0) }
        examples += [8207, 8211, 8212, 8228, 8231].map { AirPodsArtwork(family: $0 == 8207 || $0 == 8211 ? .airpods : .airpodsPro, productID: $0) }
        var result: [[String: Any]] = []
        for artwork in examples {
            let image = await poster(for: artwork)
            result.append(["family": artwork.family.rawValue, "productID": artwork.productID,
                           "colorID": artwork.colorID.map { $0 as Any } ?? NSNull(),
                           "source": url(for: artwork)?.path ?? "unavailable", "frameDecoded": image != nil,
                           "width": image?.size.width ?? 0, "height": image?.size.height ?? 0, "copiedIntoApp": false])
        }
        return result
    }
}

struct SystemAirPodsGlyph: View {
    var artwork: AirPodsArtwork
    var fallback: String
    var connected: Bool
    var size: CGFloat
    var playMovie = true
    var onPlaybackReady: (TimeInterval) -> Void = { _ in }
    var onPlaybackEnd: () -> Void = {}
    var onPlaybackFailure: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var poster: NSImage?
    @State private var playing = false
    @State private var failed = false
    @State private var finished = false

    var body: some View {
        ZStack {
            if !playing || !playMovie || reduceMotion || !connected || failed || finished {
                if let image = poster ?? SystemAirPodsArtwork.cachedPoster(for: artwork) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: fallback).font(.system(size: 26, weight: .medium))
                }
            }
            if playMovie, !reduceMotion, connected, !failed, !finished, let url = SystemAirPodsArtwork.url(for: artwork) {
                PairingMovie(url: url, onReady: { duration in
                    playing = true
                    onPlaybackReady(duration)
                }, onEnd: {
                    finished = true
                    onPlaybackEnd()
                }, onFailure: {
                    failed = true; playing = false
                    onPlaybackFailure()
                })
                    .opacity(playing ? 1 : 0)
            }
        }
        .frame(width: size, height: size).opacity(connected ? 1 : 0.4)
        .allowsHitTesting(false).accessibilityHidden(true)
        .task(id: artwork) { poster = await SystemAirPodsArtwork.poster(for: artwork) }
        .onChange(of: artwork) { _, _ in playing = false; failed = false; finished = false }
        .onChange(of: reduceMotion) { _, _ in playing = false }
    }
}

private struct PairingMovie: NSViewRepresentable {
    var url: URL
    var onReady: (TimeInterval) -> Void
    var onEnd: () -> Void
    var onFailure: () -> Void

    final class MovieView: NSView {
        let video = AVPlayerLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            video.videoGravity = .resizeAspect
            video.backgroundColor = NSColor.clear.cgColor
            layer?.addSublayer(video)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
        override func layout() { super.layout(); video.frame = bounds }
    }
    final class Coordinator {
        var url: URL?
        var player: AVPlayer?
        var readyObservation: NSKeyValueObservation?
        var failureObservation: NSKeyValueObservation?
        var playbackObservers: [NSObjectProtocol] = []
        var reportedReady = false
        func stop() {
            readyObservation = nil; failureObservation = nil
            playbackObservers.forEach { NotificationCenter.default.removeObserver($0) }
            playbackObservers.removeAll()
            player?.pause(); player?.replaceCurrentItem(with: nil)
            player = nil; url = nil; reportedReady = false
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> MovieView { MovieView(frame: .zero) }
    func updateNSView(_ view: MovieView, context: Context) {
        let state = context.coordinator
        guard state.url != url else { return }
        state.stop(); state.url = url
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        state.player = player; view.video.player = player
        state.readyObservation = view.video.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak state, weak player] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                guard let state, let player, state.player === player, !state.reportedReady else { return }
                state.reportedReady = true
                onReady(player.currentItem?.duration.seconds ?? .nan)
            }
        }
        state.failureObservation = item.observe(\.status, options: [.initial, .new]) { [weak state, weak player] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async {
                guard let state, let player, state.player === player else { return }
                onFailure()
            }
        }
        state.playbackObservers = [
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak state, weak player] _ in
                guard let state, let player, state.player === player else { return }
                onEnd()
            },
            NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak state, weak player] _ in
                guard let state, let player, state.player === player else { return }
                onFailure()
            }
        ]
        player.play()
    }
    static func dismantleNSView(_ view: MovieView, coordinator: Coordinator) {
        coordinator.stop(); view.video.player = nil
    }
}
