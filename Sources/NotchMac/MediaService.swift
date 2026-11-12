import AppKit
import Combine
import NotchCore

/// Run one AppleScript job at a time. Commands can pass reads that have not started.
@MainActor enum AppleScriptExecutor {
    private static let worker = DispatchQueue(label: "com.eduannnn.notch.applescript", qos: .userInitiated)
    private static var commands: [@Sendable () -> Void] = []
    private static var reads: [@Sendable () -> Void] = []
    private static var running = false

    static func submit(background: Bool = false, _ job: @escaping @Sendable () -> Void) {
        if background { reads.append(job) } else { commands.append(job) }
        startNext()
    }

    private static func startNext() {
        guard !running, !commands.isEmpty || !reads.isEmpty else { return }
        let job = commands.isEmpty ? reads.removeFirst() : commands.removeFirst()
        running = true
        worker.async {
            job()
            DispatchQueue.main.async {
                running = false
                startNext()
            }
        }
    }

    nonisolated static func execute(_ source: String) -> (NSAppleEventDescriptor?, Int?) {
        autoreleasepool {
            var error: NSDictionary?
            let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
            return (output, (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue)
        }
    }
}

private final class ArtworkDownload: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?
    var data: Data? {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }
}

struct MediaSnapshot {
    var identity: TrackIdentity
    var bundleID: String
    var source: String
    var duration: Double
    var position: Double
    var isPlaying: Bool
    var receivedAt = Date()
    var artwork: NSImage?
    var tint = RGB(0.286, 1, 0.996)
    var secondaryTint = RGB(0.35, 0.64, 1)
    var canControl = true
    var isBrowserAudio = false
    var artworkURL: String? = nil
    var isFavorited: Bool? = nil
    var isAppleMusic: Bool { bundleID == "com.apple.Music" && !isBrowserAudio }
    var canFavorite: Bool { isAppleMusic && canControl && isFavorited != nil && MusicFavoriteAction.script(trackID: identity.identifier, favorited: true) != nil }
    var isPreview: Bool { bundleID == "preview" }
    var currentPosition: Double { min(duration, max(0, position + (isPlaying ? Date().timeIntervalSince(receivedAt) : 0))) }
}

@MainActor final class MediaService: ObservableObject {
    @Published private(set) var snapshot: MediaSnapshot?
    @Published private(set) var deniedApps: Set<String> = []
    @Published private(set) var message = ""
    @Published private(set) var favoriteChanging = false
    private var timer: Timer?
    private var polling = false
    private var refreshRequested = false
    private var pendingPlaybackCommand: UUID?
    private var playbackObservers: [NSObjectProtocol] = []
    private(set) var playbackNotificationCount = 0
    private var artworkTrack: TrackIdentity?
    private var artworkRetryAfter = Date.distantPast
    private var artworkRequest = UUID()
    private let artworkQueue: OperationQueue = {
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
        return queue
    }()
    private var preview = false
    private var stopped = false
    private var previewTrack = 0
    private let players = [("com.spotify.client", "Spotify"), ("com.apple.Music", "Music")]

    func start() {
        stopped = false
        timer?.invalidate()
        if playbackObservers.isEmpty {
            for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
                playbackObservers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.playbackNotificationCount += 1; self?.refreshRequested = true; self?.poll() }
                })
            }
        }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
        timer?.tolerance = 0.05
    }

    func stop() {
        stopped = true; timer?.invalidate(); timer = nil
        playbackObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        playbackObservers = []; refreshRequested = false
        artworkRequest = UUID(); artworkTrack = nil; artworkQueue.cancelAllOperations()
    }

    func retryPermissions() { deniedApps = []; message = ""; poll() }

    private func poll() {
        guard !polling, pendingPlaybackCommand == nil, !preview, !stopped else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let candidates = players.filter { running.contains($0.0) && !deniedApps.contains($0.0) }
        polling = true
        refreshRequested = false
        let previous = snapshot
        AppleScriptExecutor.submit(background: true) { [weak self] in
            var results: [MediaSnapshot] = []
            var denied = Set<String>()
            for (bundle, name) in candidates.sorted(by: { ($0.0 == previous?.bundleID ? 0 : 1) < ($1.0 == previous?.bundleID ? 0 : 1) }) {
                let script = Self.readScript(bundle: bundle)
                let (result, error) = AppleScriptExecutor.execute(script)
                if error == -1743 { denied.insert(name); continue }
                guard let result, result.numberOfItems >= 7 else { continue }
                func text(_ i: Int) -> String { result.atIndex(i)?.stringValue ?? "" }
                func number(_ i: Int) -> Double { result.atIndex(i)?.doubleValue ?? 0 }
                let title = text(1)
                guard !title.isEmpty else { continue }
                let identity = TrackIdentity(source: name, identifier: text(7), title: title, artist: text(2), album: text(3))
                var item = MediaSnapshot(identity: identity, bundleID: bundle, source: name, duration: max(0, number(4)), position: max(0, number(5)), isPlaying: text(6) == "playing")
                if bundle == "com.apple.Music" {
                    let favorite = text(8)
                    item.isFavorited = favorite == "true" ? true : favorite == "false" ? false : nil
                }
                item.artworkURL = name == "Spotify" ? text(8) : nil
                if let previous {
                    item.tint = previous.tint; item.secondaryTint = previous.secondaryTint
                    if previous.identity.isSameTrack(as: identity) { item.artwork = previous.artwork }
                }
                results.append(item)
                if item.isPlaying { break }
            }
            // Preserve the current paused player when neither app is playing.
            let selected = results.first(where: \.isPlaying) ?? results.first(where: { $0.bundleID == previous?.bundleID }) ?? results.first
            let browser = selected?.isPlaying == true ? nil : SystemAudioSource.activeBrowser()
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                for name in denied { if let id = self.players.first(where: { $0.1 == name })?.0 { self.deniedApps.insert(id) } }
                if !denied.isEmpty { self.message = "Allow \(denied.sorted().joined(separator: ", ")) in System Settings → Privacy & Security → Automation." }
                // A read queued before Play/Pause still describes the old state.
                // The command completion requests a fresh read.
                if self.pendingPlaybackCommand == nil && !self.preview && !self.stopped {
                    // An artwork result can finish after this read began. Never
                    // replace that newer image with the read's empty placeholder.
                    var resolved = selected
                    if var read = resolved, let current = self.snapshot,
                       current.identity.isSameTrack(as: read.identity), let artwork = current.artwork {
                        read.artwork = artwork; read.tint = current.tint; read.secondaryTint = current.secondaryTint
                        resolved = read
                    }
                    if resolved?.isPlaying == true { self.snapshot = resolved }
                    else if let browser { self.snapshot = browser.snapshot(reusing: self.snapshot) }
                    else if self.snapshot != nil || resolved != nil { self.snapshot = resolved }
                    self.loadArtworkIfNeeded()
                    if self.refreshRequested { self.poll() }
                }
            }
        }
    }

    private func loadArtworkIfNeeded() {
        guard let item = snapshot, !item.isPreview, !item.isBrowserAudio, item.artwork == nil else { return }
        if artworkTrack?.isSameTrack(as: item.identity) == true && Date() < artworkRetryAfter { return }
        artworkTrack = item.identity; artworkRetryAfter = Date().addingTimeInterval(5)
        let request = UUID(); artworkRequest = request
        artworkQueue.cancelAllOperations()
        let apply: @Sendable (NSImage?) -> Void = { [weak self] image in
            guard let image else { return }
            let palette = Self.palette(image)
            DispatchQueue.main.async {
                guard let self, !self.stopped, !self.preview, self.artworkRequest == request,
                      var current = self.snapshot, current.bundleID == item.bundleID,
                      current.identity.isSameTrack(as: item.identity) else { return }
                current.artwork = image
                current.tint = palette.0
                current.secondaryTint = palette.1
                self.snapshot = current
            }
        }
        if item.bundleID == "com.apple.Music" {
            AppleScriptExecutor.submit(background: true) { [weak self] in
                guard self != nil else { return }
                let (result, _) = AppleScriptExecutor.execute("""
                with timeout of 3 seconds
                tell application id "com.apple.Music"
                    try
                        set t to current track
                        return {persistent ID of t as text, name of t as text, raw data of artwork 1 of t}
                    end try
                end tell
                end timeout
                """)
                guard result?.atIndex(1)?.stringValue == item.identity.identifier,
                      result?.atIndex(2)?.stringValue == item.identity.title,
                      let data = result?.atIndex(3)?.data else { return }
                apply(NSImage(data: data))
            }
        } else if item.bundleID == "com.spotify.client", let address = item.artworkURL,
                  let url = URL(string: address), url.scheme == "https" {
            artworkQueue.addOperation {
                var request = URLRequest(url: url); request.timeoutInterval = 2
                let done = DispatchSemaphore(value: 0), box = ArtworkDownload()
                let task = URLSession.shared.dataTask(with: request) { data, _, _ in box.data = data; done.signal() }
                task.resume()
                if done.wait(timeout: .now() + 2) == .timedOut { task.cancel() }
                else if let data = box.data { apply(NSImage(data: data)) }
            }
        }
    }

    func command(_ action: String) {
        guard var item = snapshot, item.canControl else { return }
        if item.isPreview {
            item.position = item.currentPosition; item.receivedAt = Date()
            if action == "playpause" { item.isPlaying.toggle() }
            else {
                previewTrack = (previewTrack + (action == "next track" ? 1 : 2)) % 3
                item.position = 0
                item.identity.identifier = "preview-\(previewTrack)"
                item.identity.title = ["Midnight on repeat", "A little after midnight", "Neon afterglow"][previewTrack]
                item.artwork = Self.previewArtwork(variant: previewTrack)
            }
            snapshot = item
            return
        }
        guard ["playpause", "next track", "previous track"].contains(action) else { return }
        if action == "playpause" {
            let request = UUID()
            pendingPlaybackCommand = request
            item.position = item.currentPosition; item.receivedAt = Date(); item.isPlaying.toggle()
            snapshot = item
            // Send the requested state so a delayed command cannot toggle a
            // state that has already changed in the player.
            let target = item.isPlaying ? "play" : "pause"
            send("with timeout of 3 seconds\ntell application id \"\(item.bundleID)\" to \(target)\nend timeout", playbackRequest: request)
        } else {
            send("with timeout of 3 seconds\ntell application id \"\(item.bundleID)\" to \(action)\nend timeout")
        }
    }

    struct AirPlayOutput: Identifiable {
        let id: Int
        let name: String
        let selected: Bool
    }

    func airPlayOutputs() async -> [AirPlayOutput]? {
        await withCheckedContinuation { continuation in
            AppleScriptExecutor.submit(background: true) {
                let (result, _) = AppleScriptExecutor.execute("""
                with timeout of 3 seconds
                tell application id "com.apple.Music"
                    set outputs to {}
                    repeat with d in AirPlay devices
                        if available of d and supports audio of d then
                            set end of outputs to {id of d, name of d, selected of d}
                        end if
                    end repeat
                    return outputs
                end tell
                end timeout
                """)
                continuation.resume(returning: result.map { list in
                    (0..<list.numberOfItems).compactMap { index in
                        guard let row = list.atIndex(index + 1),
                              let id = row.atIndex(1)?.int32Value,
                              let name = row.atIndex(2)?.stringValue else { return nil }
                        return AirPlayOutput(id: Int(id), name: name, selected: row.atIndex(3)?.booleanValue == true)
                    }
                })
            }
        }
    }

    func selectAirPlayOutput(_ output: AirPlayOutput) {
        guard snapshot?.isAppleMusic == true else { return }
        send("""
        with timeout of 5 seconds
        tell application id "com.apple.Music"
            set destination to first AirPlay device whose id is \(output.id) and available is true
            set current AirPlay devices to {destination}
        end tell
        end timeout
        """)
    }

    func toggleFavorite() {
        guard !favoriteChanging, let item = snapshot, item.canFavorite,
              let current = item.isFavorited,
              let script = MusicFavoriteAction.script(trackID: item.identity.identifier, favorited: !current) else { return }
        favoriteChanging = true
        AppleScriptExecutor.submit { [weak self] in
            let (result, error) = AppleScriptExecutor.execute(script)
            let value = result?.stringValue
            DispatchQueue.main.async {
                guard let self else { return }
                self.favoriteChanging = false
                if error == nil, let value, value == "true" || value == "false" {
                    // Only show success after Music confirms it, and never apply
                    // an old song's response to a newly selected song.
                    if self.snapshot?.bundleID == item.bundleID,
                       self.snapshot?.identity.isSameTrack(as: item.identity) == true {
                        self.snapshot?.isFavorited = value == "true"
                    }
                    self.message = ""
                } else {
                    self.message = error == -128 ? "The song changed. Try again on the current song." : "Music could not update this song’s favourite."
                }
                self.poll()
            }
        }
    }

    func seek(_ fraction: Double, on track: TrackIdentity) {
        guard var item = snapshot, item.canControl, item.identity.isSameTrack(as: track),
              let target = seekPosition(fraction: fraction, duration: item.duration) else { return }
        if !item.isPreview {
            guard item.identity.identifier == track.identifier,
                  let script = MediaSeekAction.script(bundleID: item.bundleID, trackID: track.identifier, position: target) else { return }
            let request = UUID()
            pendingPlaybackCommand = request
            send(script, playbackRequest: request)
        }
        item.position = target; item.receivedAt = Date(); snapshot = item
    }

    private func send(_ script: String, playbackRequest: UUID? = nil) {
        AppleScriptExecutor.submit { [weak self] in
            let (_, error) = AppleScriptExecutor.execute(script)
            DispatchQueue.main.async {
                guard let self else { return }
                if let playbackRequest {
                    guard self.pendingPlaybackCommand == playbackRequest else { return }
                    self.pendingPlaybackCommand = nil
                }
                if error == -128 {
                    self.message = "The song changed before Dynanotch could seek."
                } else if error != nil {
                    self.message = "The player could not complete that action. Check Automation access in System Settings."
                }
                self.poll()
            }
        }
    }

    func setPreview(_ enabled: Bool) {
        preview = enabled
        if enabled {
            snapshot = .init(identity: .init(source: "Preview", identifier: "demo-1", title: "Midnight on repeat", artist: "Dynanotch · SwiftUI preview", album: "After hours"), bundleID: "preview", source: "Preview", duration: 222, position: 74, isPlaying: true, artwork: Self.previewArtwork(), tint: RGB(0.29, 1, 0.99), secondaryTint: RGB(0.35, 0.52, 1))
        } else { snapshot = nil; poll() }
    }

    nonisolated private static func readScript(bundle: String) -> String {
        let spotify = bundle == "com.spotify.client"
        let duration = spotify ? "(duration of t) / 1000" : "duration of t"
        let identifier = spotify ? "id of t" : "persistent ID of t"
        let artwork = spotify ? ", artwork url of t as text" : ", favoriteState"
        let favoriteRead = spotify ? "" : """
            set favoriteState to "unknown"
            try
                set favoriteState to (favorited of t) as text
            end try
        """
        return """
        with timeout of 3 seconds
        tell application id "\(bundle)"
            if player state is stopped then return {}
            set t to current track
            set trackTitle to name of t as text
            set trackArtist to ""
            set trackAlbum to ""
            set trackDuration to 0
            set trackPosition to 0
            set trackIdentifier to ""
            try
                set trackArtist to artist of t as text
            end try
            try
                set trackAlbum to album of t as text
            end try
            try
                set trackDuration to \(duration)
            end try
            try
                set trackPosition to player position
            end try
            try
                set trackIdentifier to \(identifier) as text
            end try
            \(favoriteRead)
            return {trackTitle, trackArtist, trackAlbum, trackDuration, trackPosition, player state as text, trackIdentifier\(artwork)}
        end tell
        end timeout
        """
    }

    nonisolated static func palette(_ image: NSImage) -> (RGB, RGB) {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return ArtworkPalette.colors(from: []) }
        let side = 40
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return ArtworkPalette.colors(from: []) }
            context.interpolationQuality = .medium
            context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            let data = buffer.bindMemory(to: UInt8.self)
            var pixels: [RGB] = []; pixels.reserveCapacity(side * side)
            for i in stride(from: 0, to: data.count, by: 4) where data[i + 3] > 128 {
                let alpha = Double(data[i + 3])
                pixels.append(RGB(Double(data[i]) / alpha, Double(data[i + 1]) / alpha, Double(data[i + 2]) / alpha))
            }
            return ArtworkPalette.colors(from: pixels)
        }
    }

    nonisolated static func previewArtwork(variant: Int = 0) -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            let start = variant == 1 ? NSColor(red: 0.3, green: 0.05, blue: 0.24, alpha: 1) : variant == 2 ? NSColor(red: 0.22, green: 0.08, blue: 0.01, alpha: 1) : NSColor(red: 0.04, green: 0.12, blue: 0.28, alpha: 1)
            let end = variant == 1 ? NSColor(red: 0.92, green: 0.38, blue: 0.22, alpha: 1) : variant == 2 ? NSColor(red: 0.98, green: 0.7, blue: 0.12, alpha: 1) : NSColor(red: 0.05, green: 0.79, blue: 0.78, alpha: 1)
            NSGradient(starting: start, ending: end)?.draw(in: rect, angle: 45)
            NSColor(red: 0.33, green: 1, blue: 0.96, alpha: 0.8).setFill()
            NSBezierPath(ovalIn: NSRect(x: 94, y: 102, width: 106, height: 106)).fill()
            NSColor(red: 0.04, green: 0.1, blue: 0.2, alpha: 0.9).setFill()
            for i in 0..<8 { NSBezierPath(rect: NSRect(x: -20, y: i * 18, width: 300, height: 7)).fill() }
            return true
        }
    }
}
