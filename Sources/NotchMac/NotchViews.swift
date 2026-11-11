import SwiftUI
import AppKit
import NotchCore

private struct StaticNotchPreviewKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var staticNotchPreview: Bool {
        get { self[StaticNotchPreviewKey.self] }
        set { self[StaticNotchPreviewKey.self] = newValue }
    }
}

struct NotchSilhouette: Shape {
    var radius: CGFloat
    var ear: CGFloat = 7
    var closesTop = true
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(radius, ear) }
        set { radius = newValue.first; ear = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let e = min(ear, rect.height / 2), r = min(radius, (rect.width - 2 * e) / 2, rect.height - e)
        let l = rect.minX + e, right = rect.maxX - e, bottom = rect.maxY
        var path = Path()
        path.move(to: .init(x: rect.maxX, y: rect.minY))
        let k: CGFloat = 0.55228475
        path.addCurve(to: .init(x: right, y: rect.minY + e), control1: .init(x: rect.maxX - k * e, y: rect.minY), control2: .init(x: right, y: rect.minY + e - k * e))
        path.addLine(to: .init(x: right, y: bottom - r))
        path.addArc(tangent1End: .init(x: right, y: bottom), tangent2End: .init(x: right - r, y: bottom), radius: r)
        path.addLine(to: .init(x: l + r, y: bottom))
        path.addArc(tangent1End: .init(x: l, y: bottom), tangent2End: .init(x: l, y: bottom - r), radius: r)
        path.addLine(to: .init(x: l, y: rect.minY + e))
        path.addCurve(to: .init(x: rect.minX, y: rect.minY), control1: .init(x: l, y: rect.minY + e - k * e), control2: .init(x: rect.minX + k * e, y: rect.minY))
        if closesTop { path.closeSubpath() }
        return path
    }
}

struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @StateObject private var motion = NotchAnimationCoordinator()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticNotchPreview) private var staticPreview
    static let canvasWidth: CGFloat = 920
    static let canvasHeight: CGFloat = 640

    var body: some View {
        let surface = staticPreview ? model.surfaceTarget : motion.surface
        let playing = model.media.snapshot?.isPlaying == true
        let expanded = model.presentation == .expanded
        let mediaVisible = model.media.snapshot != nil && ([.collapsed, .peek, .expanded].contains(model.presentation)
            || model.preservesMediaArtwork || model.showsMediaBubble)
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                if let charge = model.trailingCharge {
                    Capsule().fill(Color.notchSurface)
                        .overlay {
                            ChargingBatteryGlyph(level: charge.battery)
                                .id(charge.id)
                                .offset(x: 1, y: 0.5)
                        }
                        .overlay {
                            SpecularGlassRim(surface: Capsule(), edge: Capsule(),
                                             highlight: model.chargePillLighting.point,
                                             strength: model.chargePillLighting.strength, staticPreview: staticPreview)
                        }
                        .frame(width: NotchModel.chargePillWidth, height: NotchModel.volumePillHeight)
                        .offset(x: (Self.canvasWidth + surface.width) / 2 + surface.offset + NotchModel.volumePillGap,
                                y: (model.collapsedHeight - NotchModel.volumePillHeight) / 2)
                        .accessibilityLabel("Charging")
                        .accessibilityValue(charge.battery.map { "\(Int($0 * 100)) percent" } ?? "")
                        .transition(reduceMotion ? .opacity : .offset(
                            x: -(NotchModel.chargePillWidth + NotchModel.volumePillGap)
                        ).combined(with: .opacity))
                }
            }
            .frame(width: Self.canvasWidth, height: Self.canvasHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            .animation(reduceMotion ? IslandMotion.fade : IslandMotion.shape, value: model.trailingCharge != nil)

            ZStack(alignment: .topLeading) {
                if let volume = model.trailingVolume {
                    Capsule().fill(Color.notchSurface)
                        .overlay {
                            Capsule().fill(.white.opacity(0.2)).frame(width: 55, height: 6)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(.white)
                                        .frame(width: volume.muted ? 0 : 55 * unit(volume.level), height: 6)
                                }
                                .overlay {
                                    if volume.muted {
                                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: volume)
                        }
                        .overlay {
                            SpecularGlassRim(surface: Capsule(), edge: Capsule(),
                                             highlight: model.volumePillLighting.point,
                                             strength: model.volumePillLighting.strength, staticPreview: staticPreview)
                        }
                        .frame(width: NotchModel.volumePillWidth, height: NotchModel.volumePillHeight)
                        .offset(x: (Self.canvasWidth + surface.width) / 2 + surface.offset + NotchModel.volumePillGap + model.volumePillExtraOffset,
                                y: (model.collapsedHeight - NotchModel.volumePillHeight) / 2)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Volume")
                        .accessibilityValue(volume.label)
                        .transition(reduceMotion ? .opacity : .offset(
                            x: -(NotchModel.volumePillWidth + NotchModel.volumePillGap)
                        ).combined(with: .opacity))
                }
            }
            .frame(width: Self.canvasWidth, height: Self.canvasHeight, alignment: .topLeading)
            .animation(reduceMotion ? IslandMotion.fade : IslandMotion.shape, value: model.trailingVolume != nil)

            ZStack(alignment: .top) {
                NotchSilhouette(radius: surface.radius, ear: surface.ear)
                    .fill(Color.notchSurface)
                    .overlay {
                        NotchGlassRim(radius: surface.radius, ear: surface.ear, highlight: model.edgeLighting.point,
                                      strength: model.edgeLighting.strength, staticPreview: staticPreview)
                    }
                    .shadow(color: .black.opacity(expanded ? 0.32 : 0), radius: 15, x: 0, y: 6)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: expanded)
                ZStack(alignment: .top) {
                    content
                        .frame(width: model.bodyWidth, height: model.bodyHeight, alignment: .top)
                        .id(model.presentation)
                        .transition(IslandMotion.content)
                }
                .animation(IslandMotion.fade, value: model.presentation)
                .frame(width: surface.width, height: surface.height, alignment: .top)
                .padding(.horizontal, surface.ear)
                .clipShape(NotchSilhouette(radius: surface.radius, ear: surface.ear))

            }
            .frame(width: surface.width + 2 * surface.ear, height: surface.height, alignment: .top)
            .offset(x: (Self.canvasWidth - surface.width) / 2 + surface.offset - surface.ear)

            ZStack(alignment: .topLeading) {
                if let notice = model.leadingAirPods, let artwork = notice.airPodsArtwork {
                    AirPodsBatterySatellite(notice: notice, model: model, system: model.system) {
                        Circle().fill(Color.notchSurface)
                            .overlay {
                                Circle().stroke(.gray.opacity(notice.battery == nil ? 0.55 : 0.25), lineWidth: 2.5)
                                    .padding(3)
                                if let battery = notice.battery {
                                    BatteryFill(level: battery) { fill in
                                        Circle().trim(from: 0, to: fill)
                                            .stroke(.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                            .rotationEffect(.degrees(-90))
                                            .padding(3)
                                    }.id(notice.id)
                                }
                                AirPodsNoticeGlyph(notice: notice, artwork: artwork, model: model, size: 22)
                                    .id("\(notice.id)/\(artwork.productID)/\(artwork.colorID ?? -1)")
                            }
                            .overlay {
                                if notice.battery == nil {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                            }
                            .frame(width: NotchModel.airPodsPillSize, height: NotchModel.airPodsPillSize)
                    }
                    .id(notice.id)
                    .frame(width: NotchModel.airPodsExpandedWidth, alignment: .trailing)
                    .offset(x: (Self.canvasWidth - surface.width) / 2 + surface.offset - model.airPodsPillOffset
                                + NotchModel.airPodsPillSize - NotchModel.airPodsExpandedWidth,
                            y: max(0, (model.collapsedHeight - NotchModel.airPodsPillSize) / 2))
                    .transition(.opacity.animation(IslandMotion.fade))
                }
            }
            .frame(width: Self.canvasWidth, height: Self.canvasHeight, alignment: .topLeading)
            .animation(reduceMotion || staticPreview ? nil : IslandMotion.fade, value: model.leadingAirPods?.id)

            if model.showsMediaBubble {
                Button { model.activateBubble() } label: {
                    Circle().fill(Color.notchSurface)
                        .overlay {
                            SpecularGlassRim(surface: Circle(), edge: Circle(), highlight: model.bubbleLighting.point,
                                             strength: model.bubbleLighting.strength, staticPreview: staticPreview)
                        }
                        .frame(width: 34, height: 34).contentShape(Circle())
                }
                .accessibilityLabel("Return to Now Playing")
                .help("Return to Now Playing")
                .offset(x: (Self.canvasWidth - surface.width) / 2 + surface.offset - 42, y: max(0, (model.collapsedHeight - 34) / 2))
                .transition(.opacity.animation(IslandMotion.fade))
            }

            FlippingArtworkView(image: model.media.snapshot?.artwork, identity: model.media.snapshot?.identity,
                                size: surface.artworkSize, radius: min(13, surface.artworkSize * 0.22),
                                onPhase: { model.recordArtworkTurn($0) })
                .scaleEffect(playing ? 1 : 0.86)
                .opacity(playing ? 1 : 0.65)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: playing)
                .offset(x: (Self.canvasWidth - surface.width) / 2 + surface.offset + surface.artworkX - surface.artworkSize / 2,
                        y: surface.artworkY - surface.artworkSize / 2)
                .opacity(mediaVisible ? 1 : 0)
                .animation(IslandMotion.fade, value: mediaVisible)
                .allowsHitTesting(false)

            // Keep foreground transition blur away from the camera throughout each morph.
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0)
                .fill(.black).frame(width: model.cameraWidth, height: model.cameraHeight)
                .offset(x: (Self.canvasWidth - model.cameraWidth) / 2)
                .allowsHitTesting(false).accessibilityHidden(true)
            if model.calibrating {
                RoundedRectangle(cornerRadius: 7).stroke(Color.notchAccent, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .frame(width: model.cameraWidth + 4, height: model.cameraHeight + 3)
                    .offset(x: (Self.canvasWidth - model.cameraWidth) / 2 - 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: Self.canvasWidth, height: Self.canvasHeight, alignment: .topLeading)
        .foregroundStyle(.white)
        .font(.system(size: 13))
        .tint(model.accent)
        .buttonStyle(.plain)
        .preferredColorScheme(.dark)
        .onAppear {
            motion.onFrame = { model.present($0) }
            motion.update(model.surfaceTarget, screen: model.displayScreen, immediate: true)
        }
        .onChange(of: model.surfaceTarget) { _, value in motion.update(value, screen: model.displayScreen) }
        .onChange(of: model.showsMediaBubble) { _, _ in model.onSurfaceChanged?() }
        .onChange(of: reduceMotion) { _, _ in motion.update(model.surfaceTarget, screen: model.displayScreen, immediate: true) }
        .onChange(of: model.hidden) { _, hidden in
            if hidden { motion.stop() } else { motion.update(model.surfaceTarget, screen: model.displayScreen, immediate: true) }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in motion.stop() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            motion.update(model.surfaceTarget, screen: model.displayScreen, immediate: true)
        }
        .onDisappear { motion.stop() }
    }

    @ViewBuilder private var content: some View {
        switch model.presentation {
        case .idle:
            Color.clear.frame(width: model.cameraWidth, height: model.collapsedHeight)
                .contentShape(Rectangle()).onTapGesture { model.openSettings?() }
                .accessibilityLabel("Dynanotch Settings")
        case .collapsed:
            HStack(spacing: 0) {
                Color.clear.frame(width: model.compactLeadingWidth)
                Color.clear.frame(width: model.cameraWidth)
                WaveformView(model: model, waveform: model.waveform).frame(width: model.compactTrailingWidth)
            }.frame(height: model.cameraHeight).contentShape(Rectangle())
                .onTapGesture { model.toggleExpansion() }
                .accessibilityLabel("Now Playing. Click to expand.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.toggleExpansion() }
        case .peek:
            VStack(spacing: 0) {
                playerHeader
                HStack(spacing: 12) {
                    Color.clear.frame(width: 40, height: 40)
                    metadata(compact: true)
                    Spacer(minLength: 4)
                    WaveformView(model: model, waveform: model.waveform)
                }.padding(.horizontal, 14).padding(.top, 2)
            }.contentShape(Rectangle()).onTapGesture { model.toggleExpansion() }
        case .expanded:
            ExpandedPlayerView(model: model, media: model.media)
        case .notice:
            if let notice = model.mainNotice { InlineNoticeView(notice: notice, model: model, cameraWidth: model.cameraWidth, leadingWidth: model.noticeLeadingWidth, trailingWidth: model.noticeTrailingWidth, height: model.cameraHeight) }
        case .osd:
            if let osd = model.osd {
                HStack(spacing: 0) {
                    if model.preservesMediaArtwork { Color.clear.frame(width: model.osdLeadingWidth) }
                    else { Image(systemName: osd.symbol).font(.system(size: 24, weight: .medium)).frame(width: model.osdLeadingWidth) }
                    Color.clear.frame(width: model.cameraWidth)
                    NotchVolumeBar(osd: osd, showsMuteMark: model.preservesMediaArtwork)
                        .frame(width: model.osdTrailingWidth)
                        .animation(IslandMotion.shape, value: osd.level)
                }.frame(height: model.cameraHeight).accessibilityElement(children: .ignore)
                    .accessibilityLabel(osd.kind == .volume ? "Volume" : "Brightness")
                    .accessibilityValue(osd.label)
            }
        }
    }

    private var playerHeader: some View {
        Color.clear.frame(height: model.cameraHeight)
    }
    private func metadata(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MarqueeText(text: model.media.snapshot?.identity.title ?? "", font: .system(size: compact ? 14 : 15, weight: .semibold))
            Text(model.media.snapshot?.identity.artist ?? "").font(.system(size: 11.5)).foregroundStyle(Color.notchSecondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NotchVolumeBar: View {
    static let width: CGFloat = 55
    let osd: SystemOSD
    let showsMuteMark: Bool
    private let height: CGFloat = 6

    var body: some View {
        Capsule().fill(.white.opacity(0.2)).frame(width: Self.width, height: height)
            .overlay(alignment: .leading) {
                Capsule().fill(.white)
                    .frame(width: osd.muted ? 0 : Self.width * unit(osd.level), height: height)
            }
            .overlay {
                if showsMuteMark && osd.muted {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
            }
    }
}

struct ExpandedPlayerView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var media: MediaService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.cameraHeight)
            HStack(spacing: 10) {
                Color.clear.frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 6) {
                    MarqueeText(text: media.snapshot?.identity.title ?? "Nothing playing", font: .system(size: 26 * model.uiScale, weight: .semibold))
                    MarqueeText(text: media.snapshot?.identity.artist ?? "", font: .system(size: 22 * model.uiScale), color: .notchSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: -7)
                WaveformView(model: model, waveform: model.waveform)
                    .offset(y: -16)
            }.padding(.horizontal, 18).padding(.top, 8)
            if let item = media.snapshot, item.canControl { SeekBar(model: model, item: item).padding(.horizontal, 24).padding(.top, 2) }
            if media.snapshot?.canControl != false {
                HStack(spacing: 7) {
                    ExpandedTransportButton("backward.fill", label: "Previous track", glyphWidth: 36, glyphHeight: 23) { media.command("previous track") }
                    ExpandedTransportButton(media.snapshot?.isPlaying == true ? "pause.fill" : "play.fill", label: media.snapshot?.isPlaying == true ? "Pause" : "Play", glyphWidth: 27, glyphHeight: 34) { media.command("playpause") }
                    ExpandedTransportButton("forward.fill", label: "Next track", glyphWidth: 36, glyphHeight: 23) { media.command("next track") }
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                if let item = media.snapshot, item.isAppleMusic {
                    Button { media.toggleFavorite() } label: {
                        Image(systemName: item.isFavorited == true ? "star.fill" : "star")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(item.isFavorited == true ? model.accent : Color.white.opacity(0.55))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.accent)
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                            .frame(width: 32, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(!item.canFavorite || media.favoriteChanging)
                    .opacity(item.canFavorite ? 1 : 0.4)
                    .accessibilityLabel(item.isFavorited == true ? "Remove favourite" : "Favourite song")
                    .accessibilityValue(item.isFavorited == true ? "Favourited" : "Not favourited")
                    .help(!item.canFavorite ? "Music does not expose favourites for this song" : item.isFavorited == true ? "Remove from favourites" : "Add to favourites")
                }
                }
                .overlay(alignment: .trailing) {
                    if media.snapshot?.isAppleMusic == true {
                        MusicAirPlayButton(model: model, media: media)
                    }
                }
                .padding(.horizontal, 24).frame(height: 44).padding(.top, 2)
            }
        }
        .offset(y: -6)
        .frame(width: model.bodyWidth)
        .overlay(alignment: .top) {
            if model.preservesMediaArtwork, let osd = model.osd {
                let collapsedCenter = (model.cameraWidth + model.osdTrailingWidth) / 2
                let insideEdge = (model.bodyWidth - NotchVolumeBar.width) / 2 - 4
                NotchVolumeBar(osd: osd, showsMuteMark: true)
                    .frame(height: model.cameraHeight)
                    .offset(x: min(collapsedCenter, insideEdge))
                    .animation(reduceMotion ? nil : IslandMotion.shape, value: osd.level)
                    .accessibilityLabel("Volume").accessibilityValue(osd.label)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: model.preservesMediaArtwork)
    }
}

private struct MusicAirPlayButton: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var media: MediaService
    @State private var showing = false
    @State private var wasPinned = false
    @State private var outputs: [MediaService.AirPlayOutput]?
    @State private var loading = false

    private var outputList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AirPlay").font(.headline)
            if loading {
                ProgressView("Finding audio outputs…").controlSize(.small)
            } else if let outputs, !outputs.isEmpty {
                ForEach(outputs) { output in
                    Button {
                        media.selectAirPlayOutput(output)
                        showing = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "speaker").frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(output.name.isEmpty ? "Unnamed audio output" : output.name)
                                    .fixedSize(horizontal: false, vertical: true)
                                if output.selected {
                                    Text("Selected").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 4)
                            if output.selected {
                                Image(systemName: "checkmark").accessibilityHidden(true)
                            }
                        }
                        .foregroundStyle(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.primary.opacity(output.selected ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(outputs == nil ? "Couldn’t load Music outputs" : "No audio outputs available")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
    }

    var body: some View {
        Button {
            wasPinned = model.pinned
            model.pinned = true
            outputs = nil
            loading = true
            showing = true
        } label: {
            Image(systemName: "airplay.audio")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("AirPlay")
        .help("Choose Apple Music output")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            outputList
            .task {
                outputs = await media.airPlayOutputs()
                loading = false
            }
        }
        .onChange(of: showing) { _, open in
            if !open { model.pinned = wasPinned }
        }
    }
}

private struct ExpandedTransportButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticNotchPreview) private var staticPreview
    @State private var skipTrigger = 0
    var symbol: String
    var label: String
    var glyphWidth: CGFloat
    var glyphHeight: CGFloat
    var action: () -> Void
    init(_ symbol: String, label: String, glyphWidth: CGFloat, glyphHeight: CGFloat, action: @escaping () -> Void) {
        self.symbol = symbol; self.label = label; self.glyphWidth = glyphWidth; self.glyphHeight = glyphHeight; self.action = action
    }
    var body: some View {
        Button {
            if symbol == "forward.fill" || symbol == "backward.fill" { skipTrigger &+= 1 }
            action()
        } label: {
            Group {
                if !staticPreview && (symbol == "forward.fill" || symbol == "backward.fill") {
                    NativeSkipGlyph(backwards: symbol == "backward.fill", trigger: skipTrigger, reduceMotion: reduceMotion)
                        .frame(width: glyphWidth, height: glyphHeight).allowsHitTesting(false)
                } else if symbol == "play.fill" || symbol == "pause.fill" {
                    // A fixed font/canvas prevents aspect-fit resizing before Magic Replace.
                    Image(systemName: symbol)
                        .font(.system(size: glyphHeight, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentTransition(symbolTransition)
                        .animation(reduceMotion ? nil : .default, value: symbol)
                        .foregroundStyle(.white.opacity(0.88))
                } else {
                    Image(systemName: symbol).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: glyphWidth, height: glyphHeight).fontWeight(.semibold)
                        .contentTransition(symbolTransition)
                        .animation(reduceMotion ? nil : .default, value: symbol)
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
                .frame(width: 56, height: 44).contentShape(Rectangle())
        }.buttonStyle(PressScaleStyle()).accessibilityLabel(label).help(label)
    }
    private var symbolTransition: ContentTransition {
        if reduceMotion { return .identity }
        if #available(macOS 15.0, *) { return .symbolEffect(.replace.magic(fallback: .replace)) }
        return .symbolEffect(.replace)
    }
}

struct SeekBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: NotchModel
    var item: MediaSnapshot
    @State private var previewRatio: Double = 0
    @State private var hover = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let position = model.scrubbing ? previewRatio * item.duration : item.currentPosition
            let ratio = item.duration > 0 ? unit(position / item.duration) : 0
            HStack(spacing: 10) {
                Text(item.duration > 0 ? clockText(position) : "–:––").frame(width: 34, alignment: .leading)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(model.accent)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.accent)
                            .frame(width: max(0, geometry.size.width * ratio))
                        if hover || model.scrubbing {
                            Circle().fill(.white).frame(width: 9, height: 9).offset(x: max(0, min(geometry.size.width - 9, geometry.size.width * ratio - 4.5)))
                        }
                    }
                    .frame(height: hover || model.scrubbing ? 6 : 4)
                    .frame(height: geometry.size.height)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard item.duration > 0 else { return }
                        previewRatio = unit(value.location.x / geometry.size.width); model.scrubbing = true
                    }.onEnded { value in
                        guard item.duration > 0 else { return }
                        model.media.seek(unit(value.location.x / geometry.size.width)); model.finishScrubbing()
                    })
                    .onHover { hover = $0 }
                    .accessibilityLabel("Playback position")
                    .accessibilityValue(clockText(position))
                    .accessibilityAdjustableAction { direction in
                        if item.duration > 0 { model.media.seek(unit((position + (direction == .increment ? 5 : -5)) / item.duration)) }
                    }
                }.frame(height: 18)
                Text(item.duration > 0 ? "−" + clockText(max(0, item.duration - position)) : "–:––").frame(width: 39, alignment: .trailing)
            }.font(.system(size: 22 * model.uiScale, weight: .medium)).monospacedDigit().foregroundStyle(Color.notchSecondary)
        }.onDisappear { if model.scrubbing { model.finishScrubbing() } }
    }
}

struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat
    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .id(ObjectIdentifier(image)).transition(.opacity)
            }
            else {
                RoundedRectangle(cornerRadius: radius).fill(Color(white: 0.13))
                    .overlay { Image(systemName: "music.note").font(.system(size: size * 0.38, weight: .medium)).foregroundStyle(Color.notchAccent) }
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .animation(IslandMotion.fade, value: image.map(ObjectIdentifier.init)).accessibilityHidden(true)
    }
}

struct WaveformView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var waveform: WaveformService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<6) { i in
                let level = !reduceMotion && waveform.active && model.media.snapshot?.isPlaying == true ? waveform.levels[i] : 0
                Capsule().fill(model.accent)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.accent)
                    .frame(width: 2.2, height: 3 + 22 * level)
            }
        }.frame(width: 26, height: 26)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.media.snapshot?.isPlaying == true)
            .accessibilityHidden(true).help(waveform.active ? "Measured live system audio" : "Allow system audio in Settings for the live waveform")
    }
}

private struct BatteryFill<Content: View>: View {
    var level: Double
    @ViewBuilder var content: (Double) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticNotchPreview) private var staticPreview
    @State private var revealed = false

    var body: some View {
        content(revealed || reduceMotion || staticPreview ? unit(level) : 0)
            .animation(reduceMotion || staticPreview ? nil : .easeOut(duration: 0.65), value: revealed)
            .animation(reduceMotion || staticPreview ? nil : .easeOut(duration: 0.35), value: level)
            .task {
                do {
                    try await Task.sleep(for: .milliseconds(40))
                    revealed = true
                } catch { }
            }
    }
}

private struct ChargingBatteryGlyph: View {
    var level: Double?

    var body: some View {
        let icon = Image(systemName: "battery.100percent.bolt")
            .font(.system(size: 28, weight: .medium))
        icon.foregroundStyle(.green.opacity(0.22))
            .overlay {
                if let level {
                    BatteryFill(level: level) { fill in
                        icon.foregroundStyle(.green)
                            .mask(alignment: .leading) {
                                GeometryReader { geometry in
                                    Rectangle().frame(width: geometry.size.width * fill)
                                }
                            }
                    }
                }
            }
    }
}

private struct AirPodsBatterySatellite<Compact: View>: View {
    var notice: DeviceNotice
    @ObservedObject var model: NotchModel
    @ObservedObject var system: SystemService
    @ViewBuilder var compact: () -> Compact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticNotchPreview) private var staticPreview

    private var details: AirPodsBatteryDetails? {
        if notice.key == "preview/airpods" { return model.previewAirPodsBatteryDetails }
        return system.state.devices.first { $0.id == notice.key && $0.connected }?.airPodsBattery
    }

    var body: some View {
        let expanded = model.heldAirPodsNotice == notice.id
        let isMax = notice.airPodsArtwork?.family == .airpodsMax
        let components: [AirPodsBatteryComponent] = isMax
            ? [.init(label: "Headphones", symbol: "airpodsmax",
                     level: details?.listeningLevel ?? notice.battery)]
            : [
                .init(label: "Charging case", symbol: symbol(.chargingCase), level: details?.chargingCase),
                .init(label: "Left AirPod", symbol: symbol(.left), level: details?.left),
                .init(label: "Right AirPod", symbol: symbol(.right), level: details?.right),
            ]
        Button {
            model.toggleAirPodsDetails(notice.id)
        } label: {
            AirPodsBatteryMorph(progress: expanded ? 1 : 0, components: components,
                               lighting: model.airPodsPillLighting, staticPreview: staticPreview,
                               compact: compact)
                .animation(reduceMotion || staticPreview ? nil : IslandMotion.satellite, value: expanded)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    guard !staticPreview else { return }
                    model.airPodsSatelliteWidth = width
                    model.onSurfaceChanged?()
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(notice.name) battery details")
        .accessibilityValue(expanded
            ? components.map { "\($0.label): \($0.reading)" }.joined(separator: ", ")
            : notice.battery.map { "\(Int(($0 * 100).rounded())) percent" } ?? "Battery level unavailable")
        .accessibilityHint(expanded ? "Collapse battery details" : "Expand battery details")
        .onDisappear {
            model.airPodsSatelliteWidth = NotchModel.airPodsPillSize
        }
    }

    private enum Part { case left, right, chargingCase }
    private func symbol(_ part: Part) -> String {
        let artwork = notice.airPodsArtwork
        let fallback: String
        let candidate: String
        switch part {
        case .left:
            fallback = "airpod.left"
            candidate = artwork?.family == .airpodsPro ? "airpodpro.left" : "airpod.gen3.left"
        case .right:
            fallback = "airpod.right"
            candidate = artwork?.family == .airpodsPro ? "airpodpro.right" : "airpod.gen3.right"
        case .chargingCase:
            fallback = "airpods.chargingcase"
            if artwork?.family == .airpodsPro {
                candidate = "airpodspro.chargingcase.wireless"
            } else if [8217, 8219, 8240, 8242, 8246, 8247].contains(artwork?.productID ?? 0) {
                candidate = "airpods.gen4.chargingcase.wireless"
            } else {
                candidate = "airpods.gen3.chargingcase.wireless"
            }
        }
        let usesModernSymbols = artwork?.family == .airpodsPro || [8211, 8217, 8219, 8240, 8242, 8246, 8247].contains(artwork?.productID ?? 0)
        return usesModernSymbols && NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil
            ? candidate : fallback
    }

}

private struct AirPodsBatteryComponent {
    var label: String
    var symbol: String
    var level: Double?
    var reading: String { level.map { "\(Int(($0 * 100).rounded()))%" } ?? "Unavailable" }
}

private struct AirPodsBatteryMorph<Compact: View>: View, Animatable {
    var progress: Double
    var components: [AirPodsBatteryComponent]
    var lighting: EdgeLighting
    var staticPreview: Bool
    @ViewBuilder var compact: () -> Compact

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let phase = unit(progress)
        let height = NotchModel.airPodsPillSize
        let expandedWidth: CGFloat = components.count == 1 ? 116 : NotchModel.airPodsExpandedWidth
        let width = height + (expandedWidth - height) * phase
        let compactOpacity = 1 - unit(phase / 0.52)
        ZStack(alignment: .leading) {
            Capsule().fill(Color.notchSurface)
            compact().frame(width: height, height: height)
                .opacity(compactOpacity)
            HStack(spacing: 0) {
                ForEach(components.indices, id: \.self) { index in
                    let component = components[index]
                    let reveal = unit((phase - [0.12, 0.46, 0.73][index]) / 0.25)
                    HStack(spacing: 5) {
                        ZStack {
                            Circle().stroke(Color(white: 0.29), lineWidth: 2.5)
                            if let level = component.level {
                                Circle().trim(from: 0, to: unit(level) * reveal)
                                    .stroke(.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            Image(systemName: component.symbol)
                                .font(.system(size: 13))
                                .foregroundStyle(.white)
                            if component.level == nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }
                        .frame(width: 26, height: 26)
                        Text(component.level == nil ? "—" : component.reading)
                            .monospacedDigit().font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(component.level == nil ? .white.opacity(0.48) : .white)
                    .frame(width: (expandedWidth - 12) / CGFloat(components.count), height: height)
                    .offset(x: -8 * (1 - reveal))
                    .opacity(reveal)
                }
            }
            .padding(.horizontal, 6)
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: width, height: height, alignment: .leading)
        .clipShape(Capsule())
        .overlay {
            SpecularGlassRim(surface: Capsule(), edge: Capsule(), highlight: lighting.point,
                             strength: lighting.strength, staticPreview: staticPreview)
                .allowsHitTesting(false)
        }
        .contentShape(Capsule())
        .accessibilityHidden(true)
    }
}

private struct AirPodsNoticeGlyph: View {
    var notice: DeviceNotice
    var artwork: AirPodsArtwork
    var model: NotchModel
    var size: CGFloat
    @Environment(\.staticNotchPreview) private var staticPreview

    var body: some View {
        SystemAirPodsGlyph(artwork: artwork, fallback: notice.kind.symbol, connected: notice.connected, size: size,
                           playMovie: !staticPreview && model.shouldPlayAirPodsMovie(notice.id),
                           onPlaybackReady: { model.airPodsMovieReady(notice.id, duration: $0) },
                           onPlaybackEnd: { model.airPodsMovieEnded(notice.id) },
                           onPlaybackFailure: { model.airPodsMovieFailed(notice.id) })
    }
}

struct InlineNoticeView: View {
    var notice: DeviceNotice
    @ObservedObject var model: NotchModel
    var cameraWidth: CGFloat
    var leadingWidth: CGFloat
    var trailingWidth: CGFloat
    var height: CGFloat
    private var color: Color { notice.kind == .batteryCritical ? .red : notice.kind == .batteryLow ? .orange : .green }
    var body: some View {
        HStack(spacing: 0) {
            Group {
                if notice.kind.isPower {
                    Text(notice.name).font(.system(size: 16, weight: .medium)).foregroundStyle(color).lineLimit(1)
                } else {
                    if notice.transport == "Bluetooth", let artwork = notice.airPodsArtwork {
                        AirPodsNoticeGlyph(notice: notice, artwork: artwork, model: model, size: min(32, height - 2))
                            .id(notice.id)
                    } else {
                        Image(systemName: notice.kind.symbol).font(.system(size: 26, weight: .medium)).opacity(notice.connected ? 1 : 0.4)
                    }
                }
            }.frame(width: leadingWidth, height: height)
            Color.clear.frame(width: cameraWidth, height: height)
            Group {
                if notice.kind.isPower {
                    HStack(spacing: 8) {
                        if let battery = notice.battery { Text("\(Int(battery * 100))%").font(.system(size: 16, weight: .semibold)).monospacedDigit() }
                        if notice.kind == .charging {
                            ChargingBatteryGlyph(level: notice.battery).id(notice.id)
                        } else {
                            Image(systemName: "battery.25percent").font(.system(size: 28, weight: .medium))
                        }
                    }.foregroundStyle(color)
                } else if let battery = notice.battery {
                    ZStack {
                        Circle().stroke(color.opacity(0.22), lineWidth: 3)
                        BatteryFill(level: battery) { fill in
                            Circle().trim(from: 0, to: fill)
                                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }.id(notice.id)
                        Text("\(Int(battery * 100))").font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(color)
                    }.frame(width: min(24, height - 4), height: min(24, height - 4))
                } else if notice.connected {
                    Circle()
                        .stroke(Color(white: 0.29), lineWidth: 3)
                        .frame(width: min(24, height - 4), height: min(24, height - 4))
                        .overlay {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.gray)
                        }
                }
            }.frame(width: trailingWidth, height: height)
        }.frame(height: height).accessibilityElement(children: .contain)
            .accessibilityLabel(notice.name + (notice.kind.isPower ? "" : notice.connected ? ", connected" : ", disconnected"))
            .accessibilityValue(notice.battery.map { "Battery \(Int($0 * 100)) percent" } ?? (notice.connected && !notice.kind.isPower ? "Battery level unavailable" : ""))
            .help(notice.name + (notice.kind.isPower ? "" : notice.connected ? " · Connected" : " · Disconnected"))
    }
}

struct SymbolButton: View {
    var symbol: String
    var label: String
    var size: CGFloat
    var action: () -> Void
    init(_ symbol: String, label: String, size: CGFloat = 14, action: @escaping () -> Void) { self.symbol = symbol; self.label = label; self.size = size; self.action = action }
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: size, weight: .semibold)).frame(minWidth: 26, minHeight: 26).contentShape(Rectangle()) }
            .buttonStyle(PressScaleStyle()).accessibilityLabel(label).help(label)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1).scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Overflow scrolls with soft edges; the fades dissolve during each reading pause.
struct MarqueeText: View {
    var text: String
    var font: Font
    var color: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var start = Date()
    var body: some View {
        GeometryReader { geometry in
            let overflow = max(0, textWidth - geometry.size.width)
            let canScroll = overflow > 2 && !reduceMotion
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !canScroll)) { context in
                let frame = RibbonFrame.at(elapsed: context.date.timeIntervalSince(start),
                                           textWidth: Double(textWidth), viewportWidth: Double(geometry.size.width))
                let moving = canScroll && frame.fadedEdges
                HStack(spacing: 36) {
                    Text(text).font(font).foregroundStyle(color).fixedSize().background {
                        GeometryReader { size in
                            Color.clear.onAppear { textWidth = size.size.width }
                                .onChange(of: size.size.width) { _, width in textWidth = width; start = Date() }
                        }
                    }
                    if canScroll { Text(text).font(font).foregroundStyle(color).fixedSize().accessibilityHidden(true) }
                }
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: canScroll ? CGFloat(frame.offset) : 0)
                .frame(width: geometry.size.width, alignment: .leading)
                    .mask {
                        HStack(spacing: 0) {
                            LinearGradient(colors: [.white.opacity(moving ? 0 : 1), .white], startPoint: .leading, endPoint: .trailing)
                                .frame(width: min(12, geometry.size.width / 4))
                            Color.white
                            LinearGradient(colors: [.white, .white.opacity(moving ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                                .frame(width: min(12, geometry.size.width / 4))
                        }
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: moving)
                    }
            }
            .onChange(of: geometry.size.width) { _, _ in start = Date() }
        }.frame(height: 19).clipped().accessibilityLabel(text).onChange(of: text) { _, _ in start = Date() }
    }
}
