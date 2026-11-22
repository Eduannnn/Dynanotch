import SwiftUI
import AppKit
import Combine
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
    var floating = false
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(radius, ear) }
        set { radius = newValue.first; ear = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        if floating { return RoundedRectangle(cornerRadius: radius).path(in: rect) }
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

private struct NotchSurfaceBackground: View {
    var surface: NotchSurface
    var liquidGlass: Bool
    var cameraHeight: CGFloat
    var expandedHeight: CGFloat
    var compactGlassHeight: CGFloat
    var floating: Bool
    var lighting: EdgeLighting
    var staticPreview: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.notchTheme) private var theme

    var body: some View {
        let shape = NotchSilhouette(radius: surface.radius, ear: surface.ear, floating: floating)
        let progress = liquidGlass && !reduceTransparency && NotchClearGlassView.isSupported
            ? unit((surface.height - compactGlassHeight - 3) / max(1, expandedHeight - compactGlassHeight - 3)) : 0
        ZStack(alignment: .top) {
            shape.fill(theme.color("surface.backgroundColor", .notchSurface)).opacity(1 - progress)
            if liquidGlass && !reduceTransparency && NotchClearGlassView.isSupported {
                NotchClearGlassBackdrop(refraction: max(0, min(100, theme.number("glass.refraction", 32))),
                    lensHeight: max(1, min(100, theme.number("glass.lensHeight", 44))), blur: max(0, min(30, theme.number("glass.blur", 0))),
                    dispersion: max(0, min(15, theme.number("glass.dispersion", 0.35))), topRadius: surface.ear, bottomRadius: surface.radius)
                    // Sample beyond the visible edge; trim the filtered surface afterward.
                    .padding(-1)
                    .clipShape(shape)
                    .opacity(progress)
                // Dimming beneath clear-glass controls, tuned to 25%.
                let dimming = unit(theme.number("glass.dimming", 0.25))
                shape.fill(.black).opacity(dimming * progress)
                    .animation(reduceMotion || staticPreview ? nil : .easeOut(duration: 0.12), value: dimming)
                LinearGradient(stops: [
                    .init(color: .black.opacity(max(0, min(1, theme.number("glass.topOpacity", 1)))), location: 0),
                    .init(color: .black.opacity(max(0, min(1, theme.number("glass.topOpacity", 1)))), location: 0.28),
                    .init(color: .black.opacity(0.75), location: 0.48),
                    .init(color: .black.opacity(0.2), location: 0.8),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: min(surface.height, cameraHeight + max(0, theme.number("glass.fadeHeight", 90))))
            }
        }
        .clipShape(shape)
        .overlay {
            let style = liquidGlass ? "glass" : "surface"
            let strength = unit(lighting.strength * theme.number(style + ".edgeHighlightIntensity", 1))
            if theme.flag(style + ".edgeHighlight", !liquidGlass) {
                if floating {
                    SpecularGlassRim(surface: RoundedRectangle(cornerRadius: surface.radius), edge: RoundedRectangle(cornerRadius: surface.radius),
                                     highlight: lighting.point, strength: strength, staticPreview: staticPreview)
                } else {
                    NotchGlassRim(radius: surface.radius, ear: surface.ear, highlight: lighting.point,
                                  strength: strength, staticPreview: staticPreview)
                }
            }
        }
    }
}

private struct ThemedBubbleRim<S: Shape>: View {
    @Environment(\.notchTheme) private var theme
    let shape: S
    let lighting: EdgeLighting
    let prefersLiquidGlass: Bool
    let staticPreview: Bool

    var body: some View {
        let liquidGlass = theme.flag("glass.enabled", prefersLiquidGlass)
        let style = liquidGlass ? "glass" : "surface"
        if theme.flag(style + ".edgeHighlight", !liquidGlass) {
            SpecularGlassRim(surface: shape, edge: shape, highlight: lighting.point,
                             strength: unit(lighting.strength * theme.number(style + ".edgeHighlightIntensity", 1)),
                             staticPreview: staticPreview)
                .allowsHitTesting(false)
        }
    }
}

struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @StateObject private var motion = NotchAnimationCoordinator()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticNotchPreview) private var staticPreview
    static let canvasWidth: CGFloat = 920
    static let canvasHeight: CGFloat = 640
    fileprivate static let canvasSpace = "notch-canvas"

    var body: some View {
        let surface = staticPreview ? model.surfaceTarget : motion.surface
        let playing = model.media.snapshot?.isPlaying == true
        let expanded = model.presentation == .expanded
        let waveformVisible = model.media.snapshot != nil && [.collapsed, .peek, .expanded].contains(model.presentation)
        let mediaVisible = waveformVisible || model.showsMediaBubble
        let left = (Self.canvasWidth - surface.width) / 2 + surface.offset
        let right = left + surface.width
        let satelliteY = max(0, (model.collapsedHeight - model.bubbleSize) / 2)
        ZStack(alignment: .topLeading) {
            if model.chargingTakeover == nil {
                BubbleSatellite(model: model, kind: .charge, item: model.lockScreenNotice,
                                lane: .init(edge: right, y: satelliteY, width: model.bubbleSize, side: .trailing)) { notice in
                    Capsule().fill(model.theme.element("bubble.charging").color("backgroundColor", .notchSurface))
                        .overlay {
                            if notice.kind.isPower {
                                PowerBatteryGlyph(kind: notice.kind, level: notice.battery, size: 14)
                                    .id(notice.id)
                                    .offset(x: -0.5, y: 0)
                            } else {
                                Image(systemName: notice.kind.symbol)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(notice.connected ? 1 : 0.6))
                            }
                        }
                        .overlay {
                            ThemedBubbleRim(shape: Capsule(), lighting: model.chargePillLighting,
                                            prefersLiquidGlass: model.preferences.liquidGlass, staticPreview: staticPreview)
                        }
                        .frame(width: model.bubbleSize, height: model.bubbleSize)
                        .themed("bubble.charging")
                        .accessibilityLabel(notice.kind == .charging ? "Charging" : notice.name)
                        .accessibilityValue(notice.battery.map { "\(Int($0 * 100)) percent" } ?? "")
                }
                .allowsHitTesting(false)

                BubbleSatellite(model: model, kind: .airPods, item: model.leadingAirPods,
                                lane: .init(edge: left, y: satelliteY, width: model.bubbleSize,
                                            side: .leading, occupiedWidth: model.airPodsPillOffset - (model.bubbleSize + model.bubbleGap))) { notice in
                    if let artwork = notice.airPodsArtwork {
                        AirPodsBatterySatellite(notice: notice, model: model, system: model.system) {
                            Circle().fill(model.theme.element("bubble.airpods").color("backgroundColor", .notchSurface))
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
                                    AirPodsNoticeGlyph(notice: notice, artwork: artwork, model: model, size: 18)
                                        .id("\(notice.id)/\(artwork.productID)/\(artwork.colorID ?? -1)")
                                }
                                .overlay {
                                    if notice.battery == nil {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.65))
                                    }
                                }
                                .frame(width: model.bubbleSize, height: model.bubbleSize)
                        }
                        .id(notice.id)
                        .themed("bubble.airpods")
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }

                if model.osd == nil {
                    BubbleSatellite(model: model, kind: .music, item: model.showsMediaBubble || model.showsLockBubble ? true : nil,
                                    lane: .init(edge: left, y: satelliteY, width: model.bubbleSize, side: .leading)) { _ in
                        Button { model.activateBubble() } label: {
                            Circle().fill(model.theme.element(model.showsLockBubble ? "bubble.lock" : "bubble.music").color("backgroundColor", .notchSurface))
                                .overlay {
                                    ThemedBubbleRim(shape: Circle(), lighting: model.bubbleLighting,
                                                    prefersLiquidGlass: model.preferences.liquidGlass, staticPreview: staticPreview)
                                }
                                .overlay {
                                    if model.showsLockBubble {
                                        Image(systemName: model.theme.string(model.screenLocked ? "symbols.locked" : "symbols.unlocked", model.screenLocked ? "lock.fill" : "lock.open.fill"))
                                            .font(.system(size: 14, weight: .semibold))
                                            .contentTransition(reduceMotion || staticPreview ? .identity : symbolReplaceTransition)
                                            .animation(reduceMotion || staticPreview ? nil : .easeInOut(duration: 0.24), value: model.screenLocked)
                                    }
                                }
                                .frame(width: model.bubbleSize, height: model.bubbleSize).contentShape(Circle())
                        }
                        .themed(model.showsLockBubble ? "bubble.lock" : "bubble.music")
                        .allowsHitTesting(!model.showsLockBubble)
                        .accessibilityLabel(model.showsLockBubble ? (model.screenLocked ? "Mac locked" : "Mac unlocked") : "Return to Now Playing")
                        .help(model.showsLockBubble ? "Mac locked" : "Return to Now Playing")
                    }
                }
            }

            ZStack(alignment: .top) {
                NotchSurfaceBackground(surface: surface, liquidGlass: model.theme.flag("glass.enabled", model.preferences.liquidGlass),
                                       cameraHeight: model.cameraHeight,
                                       expandedHeight: model.cameraHeight + (model.media.snapshot?.isBrowserAudio == true ? 84 : 146) - 2,
                                       compactGlassHeight: model.presentation == .osd ? model.contentHeight : model.cameraHeight,
                                       floating: !model.hasHardwareNotch, lighting: model.edgeLighting, staticPreview: staticPreview)
                    .themed("surface")
                    .shadow(color: .black.opacity(expanded ? (model.theme.flag("glass.enabled", model.preferences.liquidGlass) ? model.theme.number("glass.shadowOpacity", 0) : model.theme.number("surface.shadowOpacity", 0.32)) : 0),
                            radius: model.theme.number("surface.shadowRadius", 15), x: model.theme.number("surface.shadowX", 0), y: model.theme.number("surface.shadowY", 6))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: expanded)
                ZStack(alignment: model.inlineAirPods == nil ? .top : .topLeading) {
                    content
                        .frame(width: model.bodyWidth, height: model.contentHeight, alignment: .top)
                        .id(model.presentation)
                        .transition(IslandMotion.content)
                }
                .animation(IslandMotion.fade, value: model.presentation)
                .frame(width: surface.width, height: surface.height, alignment: model.inlineAirPods == nil ? .top : .topLeading)
                .overlay(alignment: .topLeading) {
                    WaveformView(model: model, waveform: model.waveform, visible: waveformVisible)
                        .themed("waveform")
                        .position(x: surface.width - surface.waveformInset, y: surface.waveformY)
                        .opacity(waveformVisible ? 1 : 0)
                        .animation(IslandMotion.fade, value: waveformVisible)
                        .allowsHitTesting(false)

                }
                .padding(.horizontal, surface.ear)
                .clipShape(NotchSilhouette(radius: surface.radius, ear: surface.ear, floating: !model.hasHardwareNotch))

                if expanded {
                    Button { model.close() } label: {
                        Color.clear
                            .frame(width: surface.width, height: model.cameraHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Collapse player")
                }

            }
            .frame(width: surface.width + 2 * surface.ear, height: surface.height, alignment: .top)
            .offset(x: (Self.canvasWidth - surface.width) / 2 + surface.offset - surface.ear)

            FlippingArtworkView(image: model.media.snapshot?.artwork, identity: model.media.snapshot?.identity,
                                flipsBackward: model.media.artworkFlipsBackward,
                                size: surface.artworkSize, radius: model.theme.number("layout.artworkRadius", min(13, surface.artworkSize * 0.22)),
                                onPhase: { model.recordArtworkTurn($0) })
                .themed("artwork")
                .scaleEffect(playing ? 1 : 0.86)
                .opacity(playing ? 1 : 0.65)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: playing)
                .offset(x: (Self.canvasWidth - surface.width) / 2 + surface.offset + surface.artworkX - surface.artworkSize / 2,
                        y: surface.artworkY - surface.artworkSize / 2)
                .opacity(mediaVisible ? 1 : 0)
                .animation(IslandMotion.fade, value: mediaVisible)
                .allowsHitTesting(false)

            NotchThemeLayers(model: model, outerRadius: min(surface.radius, surface.width / 2, surface.height - surface.ear))
                .frame(width: surface.width, height: surface.height, alignment: .topLeading)
                .clipShape(NotchSilhouette(radius: surface.radius, ear: surface.ear, floating: !model.hasHardwareNotch))
                .offset(x: (Self.canvasWidth - surface.width) / 2 + surface.offset)

            // Keep foreground transition blur away from the camera throughout each morph.
            if model.hasHardwareNotch {
                NotchSilhouette(radius: 12, ear: 0)
                    .fill(.black).frame(width: model.cameraWidth, height: model.cameraHeight)
                    .offset(x: (Self.canvasWidth - model.cameraWidth) / 2)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            if model.calibrating {
                RoundedRectangle(cornerRadius: 7).stroke(Color.notchAccent, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .frame(width: model.cameraWidth + 4, height: model.cameraHeight + 3)
                    .offset(x: (Self.canvasWidth - model.cameraWidth) / 2 - 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: Self.canvasWidth, height: Self.canvasHeight, alignment: .topLeading)
        .coordinateSpace(name: Self.canvasSpace)
        .scaleEffect(model.notchScale, anchor: .top)
        .opacity(!model.hasHardwareNotch && model.presentation == .idle && model.idlePillPhase == .hidden ? 0 : 1)
        .animation(IslandMotion.fade, value: model.idlePillPhase)
        .foregroundStyle(.white)
        .font(.system(size: 13))
        .tint(model.accent)
        .buttonStyle(.plain)
        .preferredColorScheme(.dark)
        .environment(\.notchTheme, model.theme)
        .onAppear {
            if model.idlePillPhase == .pill { model.updateIdlePill() }
            motion.response = model.theme.number("motion.response", 0.32)
            motion.damping = model.theme.number("motion.damping", 0.88)
            motion.onFrame = { model.present($0) }
            motion.update(model.surfaceTarget, screen: model.displayScreen, immediate: true)
        }
        .notchOnChange(of: model.presentation) { _, _ in model.updateIdlePill() }
        .notchOnChange(of: model.hasHardwareNotch) { _, _ in model.updateIdlePill() }
        .notchOnChange(of: model.surfaceTarget) { _, value in
            motion.response = !model.hasHardwareNotch && model.presentation == .idle && model.idlePillPhase == .shrinking
                ? max(0.05, model.theme.number("motion.idleShrinkResponse", 0.65))
                : max(0.05, model.theme.number("motion.response", 0.32))
            motion.damping = max(0.1, model.theme.number("motion.damping", 0.88))
            motion.update(value, screen: model.displayScreen)
        }
        .notchOnChange(of: model.showsMediaBubble) { _, _ in model.onSurfaceChanged?() }
        .notchOnChange(of: reduceMotion) { _, _ in motion.update(model.surfaceTarget, screen: model.displayScreen, immediate: true) }
        .notchOnChange(of: model.hidden) { _, hidden in
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
            if model.showsLockLayout {
                HStack(spacing: 0) {
                    Image(systemName: model.theme.string(model.screenLocked ? "symbols.locked" : "symbols.unlocked", model.screenLocked ? "lock.fill" : "lock.open.fill"))
                        .font(.system(size: 14, weight: .semibold))
                        .contentTransition(reduceMotion || staticPreview ? .identity : symbolReplaceTransition)
                        .animation(reduceMotion || staticPreview ? nil : .easeInOut(duration: 0.24), value: model.screenLocked)
                        .opacity(model.isUnlocking && !staticPreview ? 0 : 1)
                        .animation(model.isUnlocking && !reduceMotion && !staticPreview
                            ? .easeOut(duration: 0.12).delay(0.27) : nil, value: model.isUnlocking)
                        .frame(width: model.compactLeadingWidth)
                        .accessibilityLabel(model.screenLocked ? "Mac locked" : "Mac unlocked")
                    Color.clear.frame(width: model.cameraWidth)
                }
                .frame(height: model.cameraHeight)
                .allowsHitTesting(false)
            } else {
                Color.clear.frame(width: model.hasHardwareNotch ? model.cameraWidth : model.surfaceTarget.width, height: model.collapsedHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        case .collapsed:
            HStack(spacing: 0) {
                Color.clear.frame(width: model.compactLeadingWidth)
                Color.clear.frame(width: model.cameraWidth)
                Color.clear.frame(width: model.compactTrailingWidth)
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
                    Color.clear.frame(width: WaveformView.width)
                }.padding(.horizontal, 14).padding(.top, 2)
            }.contentShape(Rectangle()).onTapGesture { model.toggleExpansion() }
        case .expanded:
            ExpandedPlayerView(model: model, media: model.media)
        case .notice:
            if let notice = model.mainNotice {
                let header = InlineNoticeView(notice: notice, model: model, cameraWidth: model.cameraWidth,
                                              leadingWidth: model.noticeLeadingWidth, trailingWidth: model.noticeTrailingWidth,
                                              height: model.cameraHeight)
                if model.inlineAirPods != nil {
                    header.themed("notice")
                        .contentShape(Rectangle())
                        .onTapGesture { model.toggleAirPodsDetails(notice.id) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { model.toggleAirPodsDetails(notice.id) }
                    .accessibilityHint(model.showsInlineAirPodsDetails ? "Collapse battery details" : "Expand battery details")
                    .animation(reduceMotion || staticPreview ? nil : IslandMotion.satellite, value: model.showsInlineAirPodsDetails)
                } else {
                    header.themed("notice")
                }
            }
        case .osd:
            if let osd = model.osd {
                GeometryReader { geometry in
                    let layout = model.design.osdLayout(width: geometry.size.width, cameraHeight: model.cameraHeight,
                                                        hasNotch: model.hasHardwareNotch, wingLimit: model.compactLeadingWidth)

                    osdIcon(osd, size: layout.iconSize)
                        .position(layout.iconCenter)
                    NotchVolumeBar(osd: osd, width: layout.barWidth)
                        .position(layout.barCenter)
                    Text(osd.percentageText)
                        .font(.system(size: NotchDesign.OSDLayout.percentageFontSize, weight: .medium).monospacedDigit())
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: layout.percentageWidth, alignment: .leading)
                        .position(layout.percentageCenter)
                }
                .frame(height: model.contentHeight)
                .offset(x: model.osdTrailingInset / 2)
                .themed("osd")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(osd.kind == .volume ? "Volume" : "Brightness")
                .accessibilityValue(osd.label)
            }
        }
    }

    private func osdIcon(_ osd: SystemOSD, size: CGFloat) -> some View {
        let level = unit(osd.level)
        let themeKey: String
        let fallback: String
        if osd.kind == .brightness {
            themeKey = "symbols.brightness"
            fallback = level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        } else if osd.muted || level == 0 {
            themeKey = "symbols.muted"
            fallback = "speaker.slash.fill"
        } else {
            themeKey = "symbols.volume"
            fallback = level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }
        let symbol = model.theme.string(themeKey, fallback)
        let animates = !reduceMotion && !staticPreview
        return Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
            .frame(height: size * 1.25)
            .contentTransition(animates ? .symbolEffect(.replace.downUp.byLayer) : .identity)
            .animation(animates ? .easeInOut(duration: 0.14) : nil, value: symbol)
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

private struct BubbleLane {
    let edge: CGFloat
    let y: CGFloat
    let width: CGFloat
    let side: HorizontalEdge
    var occupiedWidth: CGFloat = 0
    var height: CGFloat = 32
    var gap: CGFloat = 8

    var direction: CGFloat { side == .leading ? -1 : 1 }
    var restGap: CGFloat { gap }
}

private struct BubbleSatellite<Item: Equatable, Content: View>: View {
    let model: NotchModel
    let kind: NotchSatellite
    let item: Item?
    let lane: BubbleLane
    @ViewBuilder var content: (Item) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticNotchPreview) private var staticPreview
    @State private var retainedItem: Item?
    @State private var reservedWidth: CGFloat = 0

    var body: some View {
        var displayedLane = lane
        displayedLane.height = model.bubbleSize
        displayedLane.gap = model.bubbleGap
        if !reduceMotion && !staticPreview {
            displayedLane.occupiedWidth = max(lane.occupiedWidth, reservedWidth)
        }
        return BubbleFlight(progress: item == nil ? 0 : 1, lane: displayedLane, moves: !reduceMotion && !staticPreview) {
            if let displayed = item ?? retainedItem {
                content(displayed)
                    .notchOnGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(NotchRootView.canvasSpace))
                    } action: { frame in
                        if !staticPreview { model.presentSatellite(kind, frame: frame) }
                    }
                    .onDisappear {
                        if !staticPreview { model.presentSatellite(kind, frame: nil) }
                    }
            }
        }
        .animation(staticPreview ? nil : reduceMotion ? IslandMotion.fade : IslandMotion.bubble, value: item != nil)
        .animation(reduceMotion || staticPreview ? nil : .easeOut(duration: 0.16), value: displayedLane.occupiedWidth)
        .allowsHitTesting(item != nil)
        .accessibilityHidden(item == nil)
        .notchOnChange(of: item, initial: true) { _, current in
            // Keep the outgoing content available for the spring, including on a rapid reversal.
            if let current { retainedItem = current }
        }
        .task(id: lane.occupiedWidth) {
            guard !reduceMotion && !staticPreview else { return }
            if lane.occupiedWidth > 0 {
                reservedWidth = lane.occupiedWidth
            } else if reservedWidth > 0 {
                // Leave room for the inner satellite while its removal spring is still running.
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                reservedWidth = 0
            }
        }
    }
}

private struct BubbleFlight<Content: View>: View, Animatable {
    var progress: CGFloat
    var lane: BubbleLane
    let moves: Bool
    @ViewBuilder var content: () -> Content

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(progress, lane.occupiedWidth) }
        set {
            progress = newValue.first
            lane.occupiedWidth = newValue.second
        }
    }

    var body: some View {
        let phase = unit(progress)
        let occupiedWidth = max(0, lane.occupiedWidth)
        let openLane = 1 - unit(occupiedWidth / lane.restGap)
        let travel = 4 + (lane.width + lane.restGap - 2) * openLane
        // Give the exposed bridge more time than the travel hidden behind the island.
        let remaining = (1 - phase) * (1 - phase) * (1 + 0.4 * phase)
        let gap = lane.restGap + occupiedWidth - (moves ? travel * remaining : 0)
        let left = lane.edge + lane.direction * gap - (lane.side == .leading ? lane.width : 0)
        let height = lane.height
        let reveal = unit((gap + lane.width * 0.65) / (lane.width * 0.65))
        let emergence = reveal * reveal * (3 - 2 * reveal)
        let contentOpacity = moves ? emergence * openLane + phase * (1 - openLane) : phase

        ZStack(alignment: .topLeading) {
            if phase > 0 {
                if moves && occupiedWidth < 0.5 && gap > -7 && gap < lane.restGap {
                    let overlap: CGFloat = 8
                    let span = gap + 2 * overlap
                    LiquidBubbleBridge(gap: gap, restGap: lane.restGap, overlap: overlap)
                        .fill(Color.notchSurface)
                        .frame(width: span, height: height)
                        .offset(x: lane.side == .leading ? lane.edge - gap - overlap : lane.edge - overlap,
                                y: lane.y)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                ZStack(alignment: .trailing) {
                    if moves && occupiedWidth < 0.5 {
                        Capsule().fill(Color.notchSurface)
                    }
                    content().opacity(contentOpacity)
                }
                .frame(width: lane.width, height: height, alignment: .trailing)
                .offset(x: left, y: lane.y)
            }
        }
        .frame(width: NotchRootView.canvasWidth, height: NotchRootView.canvasHeight, alignment: .topLeading)
    }
}

private struct LiquidBubbleBridge: Shape {
    let gap: CGFloat
    let restGap: CGFloat
    let overlap: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = rect.midY
        let snapGap = restGap * 0.9
        let stretch = unit(max(0, gap) / snapGap)
        let neck = 8 * (1 - stretch * stretch * stretch)
        let separation = unit((gap - snapGap) / (restGap - snapGap))
        let tipReach = (rect.width / 2 - overlap + 2) * (1 - separation)
        let shoulder: CGFloat = 11

        // Both halves share a horizontal tangent at the neck. After pinching shut,
        // their tips retract into the original silhouettes with no opacity seam.
        var path = Path()
        for direction: CGFloat in [1, -1] {
            let start = direction > 0 ? rect.minX : rect.maxX
            let tip = start + direction * (overlap - 2 + tipReach)
            let distance = abs(tip - start)
            let control = start + direction * distance * 0.62
            path.move(to: CGPoint(x: start, y: center - shoulder))
            path.addCurve(to: CGPoint(x: tip, y: center - neck),
                          control1: CGPoint(x: control, y: center - shoulder),
                          control2: CGPoint(x: tip - direction * distance * 0.28, y: center - neck))
            path.addLine(to: CGPoint(x: tip, y: center + neck))
            path.addCurve(to: CGPoint(x: start, y: center + shoulder),
                          control1: CGPoint(x: tip - direction * distance * 0.28, y: center + neck),
                          control2: CGPoint(x: control, y: center + shoulder))
            path.closeSubpath()
        }
        return path
    }
}

private struct NotchProgressTrack: View {
    let level: Double
    let tint: Color
    var backgroundOpacity = 0.2

    var body: some View {
        GeometryReader { geometry in
            let progress = unit(level)
            let trackWidth = geometry.size.width
            let trackHeight = min(geometry.size.height, trackWidth)
            let fillWidth = progress > 0 ? min(trackWidth, max(1, trackWidth * progress)) : 0
            let fillHeight = min(trackHeight, fillWidth)
            let leadingInset = (trackHeight - fillHeight) / 2

            Capsule(style: .circular).fill(.white.opacity(backgroundOpacity))
                .overlay(alignment: .leading) {
                    Capsule(style: .circular).fill(tint)
                        .frame(width: fillWidth, height: fillHeight)
                        .offset(x: leadingInset)
                }
        }
    }
}

private struct NotchVolumeBar: View {
    static let standardWidth: CGFloat = 55
    let osd: SystemOSD
    var width: CGFloat = NotchVolumeBar.standardWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let height = NotchDesign.OSDLayout.barHeight
        let volume = osd.muted ? 0 : osd.level
        GeometryReader { geometry in
            let progress = min(max(volume, 0), 1)
            let fillWidth = geometry.size.width * progress
            let tipRadius = min(height / 2, fillWidth / 2)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.2))

                RoundedRectangle(cornerRadius: tipRadius, style: .circular)
                    .fill(.white)
                    .frame(width: fillWidth)
            }
            .frame(height: height)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: volume)
        }
        .frame(width: width, height: height)

    }
}

struct ExpandedPlayerView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var media: MediaService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.cameraHeight)
            HStack(spacing: model.design.horizontalSpacing) {
                Color.clear.frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: model.design.verticalSpacing) {
                    MarqueeText(text: media.snapshot?.identity.title ?? "Nothing playing", font: .system(size: model.theme.element("title").number("fontSize", 26 * model.uiScale), weight: .semibold), color: model.theme.element("title").color("color", .white)).themed("title")
                    MarqueeText(text: media.snapshot?.identity.artist ?? "", font: .system(size: model.theme.element("artist").number("fontSize", 22 * model.uiScale)), color: model.theme.element("artist").color("color", model.theme.color("colors.secondaryColor", .notchSecondary))).themed("artist")
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: model.theme.number("layout.metadataY", -7)).themed("metadata")
                Color.clear.frame(width: model.expandedWaveformInset + WaveformView.width / 2 - 18)
            }.padding(.horizontal, model.design.headerPadding).padding(.top, model.design.headerTop)
            if let item = media.snapshot, item.canControl { SeekBar(model: model, item: item).themed("progress").padding(.horizontal, model.design.progressPadding).padding(.top, model.theme.number("layout.progressTop", 2)) }
            if media.snapshot?.canControl != false {
                HStack(spacing: model.design.controlSpacing) {
                    ExpandedTransportButton("backward.fill", label: "Previous track", glyphWidth: 36, glyphHeight: 23) { media.command("previous track") }.themed("previous")
                    ExpandedTransportButton(media.snapshot?.isPlaying == true ? "pause.fill" : "play.fill", label: media.snapshot?.isPlaying == true ? "Pause" : "Play", glyphWidth: 27, glyphHeight: 34) { media.command("playpause") }.themed("playPause")
                    ExpandedTransportButton("forward.fill", label: "Next track", glyphWidth: 36, glyphHeight: 23) { media.command("next track") }.themed("next")
                }
                .frame(maxWidth: .infinity).themed("controls")
                .overlay(alignment: .leading) {
                if let item = media.snapshot, item.isAppleMusic {
                    Button { media.toggleFavorite() } label: {
                        FavoriteStar(isFavorited: item.isFavorited == true, accent: model.accent)
                            .id(item.identity.identifier)
                            .frame(width: 32, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle()).themed("favorite")
                    .disabled(!item.canFavorite || media.favoriteChanging)
                    .opacity(item.canFavorite ? 1 : 0.4)
                    .accessibilityLabel(item.isFavorited == true ? "Remove favourite" : "Favourite song")
                    .accessibilityValue(item.isFavorited == true ? "Favourited" : "Not favourited")
                    .help(!item.canFavorite ? "Music does not expose favourites for this song" : item.isFavorited == true ? "Remove from favourites" : "Add to favourites")
                }
                }
                .overlay(alignment: .trailing) {
                    if media.snapshot?.isAppleMusic == true {
                        MusicAirPlayButton(model: model, media: media).themed("airplay")
                    }
                }
                .padding(.horizontal, model.design.controlsPadding).frame(height: 44).padding(.top, model.theme.number("layout.controlsTop", 2))
            }
        }
        .offset(y: -6)
        .frame(width: model.bodyWidth)
    }
}

private struct FavoriteStar: View {
    @Environment(\.notchTheme) private var theme
    let isFavorited: Bool
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Motion {
        var scale = 1.0
        var glow = 0.0
        var fadingFill = 0.0
    }

    private func star(filled: Bool) -> some View {
        Image(systemName: theme.string(filled ? "symbols.favorited" : "symbols.favorite", filled ? "star.fill" : "star"))
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(theme.element("favorite").color("color", filled ? accent : Color.white.opacity(0.55)))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: accent)
    }

    var body: some View {
        if reduceMotion {
            star(filled: isFavorited)
        } else if #available(macOS 14.0, *) {
            KeyframeAnimator(initialValue: Motion(), trigger: isFavorited) { motion in
                let fill = unit(motion.fadingFill)
                star(filled: isFavorited)
                    .opacity(isFavorited ? 1 : 1 - fill)
                    .overlay {
                        if !isFavorited {
                            star(filled: true).opacity(fill)
                        }
                    }
                    .scaleEffect(motion.scale)
                    .background {
                        RadialGradient(colors: [.white.opacity(0.38), .clear],
                                       center: .center, startRadius: 1, endRadius: 29)
                            .frame(width: 58, height: 58)
                            .opacity(unit(motion.glow))
                            .allowsHitTesting(false)
                    }
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(isFavorited ? 1.30 : 0.92, duration: isFavorited ? 0.05 : 0.10)
                    CubicKeyframe(isFavorited ? 1.44 : 0.94, duration: isFavorited ? 0.24 : 0.06)
                    CubicKeyframe(isFavorited ? 0.90 : 1.00, duration: isFavorited ? 0.18 : 0.13)
                    CubicKeyframe(1.00, duration: isFavorited ? 0.23 : 0.02)
                }
                KeyframeTrack(\.glow) {
                    LinearKeyframe(isFavorited ? 0.55 : 0, duration: 0.04)
                    CubicKeyframe(isFavorited ? 0.48 : 0, duration: isFavorited ? 0.25 : 0.10)
                    CubicKeyframe(0, duration: isFavorited ? 0.36 : 0.13)
                }
                KeyframeTrack(\.fadingFill) {
                    MoveKeyframe(isFavorited ? 0 : 1)
                    CubicKeyframe(0, duration: 0.18)
                }
            }
        } else {
            star(filled: isFavorited).animation(.spring(response: 0.25, dampingFraction: 0.8), value: isFavorited)
        }
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
        VStack(alignment: .leading, spacing: model.design.small) {
            Text("AirPlay").font(.headline)
            if loading {
                ProgressView("Finding audio outputs…").controlSize(.small)
            } else if let outputs, !outputs.isEmpty {
                ForEach(outputs) { output in
                    Button {
                        media.selectAirPlayOutput(output)
                        showing = false
                    } label: {
                        HStack(spacing: model.design.horizontalSpacing) {
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
                        .padding(model.design.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.primary.opacity(output.selected ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: model.design.innerRadius))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(outputs == nil ? "Couldn’t load Music outputs" : "No audio outputs available")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(model.design.popoverPadding)
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
        .notchOnChange(of: showing) { _, open in
            if !open { model.pinned = wasPinned }
        }
    }
}

private var symbolReplaceTransition: ContentTransition {
    if #available(macOS 15.0, *) { return .symbolEffect(.replace.magic(fallback: .replace)) }
    if #available(macOS 14.0, *) { return .symbolEffect(.replace) }
    return .opacity
}

private struct ExpandedTransportButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticNotchPreview) private var staticPreview
    @State private var skipTrigger = 0
    @Environment(\.notchTheme) private var theme
    private var element: NotchTheme { theme.element(symbol == "backward.fill" ? "previous" : symbol == "forward.fill" ? "next" : "playPause") }
    var symbol: String
    var label: String
    var glyphWidth: CGFloat
    var glyphHeight: CGFloat
    var action: () -> Void
    private var displaySymbol: String {
        theme.string("symbols." + (symbol == "backward.fill" ? "previous" : symbol == "forward.fill" ? "next" : symbol == "play.fill" ? "play" : "pause"), symbol)
    }
    private var isPlayPause: Bool { symbol == "play.fill" || symbol == "pause.fill" }

    init(_ symbol: String, label: String, glyphWidth: CGFloat, glyphHeight: CGFloat, action: @escaping () -> Void) {
        self.symbol = symbol; self.label = label; self.glyphWidth = glyphWidth; self.glyphHeight = glyphHeight; self.action = action
    }
    var body: some View {
        Button {
            if symbol == "forward.fill" || symbol == "backward.fill" { skipTrigger &+= 1 }
            action()
        } label: {
            Group {
                if !staticPreview && displaySymbol == symbol && (symbol == "forward.fill" || symbol == "backward.fill") {
                    NativeSkipGlyph(backwards: symbol == "backward.fill", trigger: skipTrigger, reduceMotion: reduceMotion)
                        .frame(width: element.number("glyphWidth", glyphWidth), height: element.number("glyphHeight", glyphHeight)).colorMultiply(element.color("color", .white)).allowsHitTesting(false)
                } else if isPlayPause {
                    // A fixed font/canvas prevents aspect-fit resizing before Magic Replace.
                    Image(systemName: displaySymbol)
                        .font(.system(size: element.number("fontSize", glyphHeight), weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentTransition(symbolTransition)
                        .animation(reduceMotion ? nil : .default, value: symbol)
                        .foregroundStyle(element.color("color", .white.opacity(0.88)))
                } else {
                    Image(systemName: displaySymbol).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: element.number("glyphWidth", glyphWidth), height: element.number("glyphHeight", glyphHeight)).fontWeight(.semibold)
                        .contentTransition(symbolTransition)
                        .animation(reduceMotion ? nil : .default, value: symbol)
                        .foregroundStyle(element.color("color", .white.opacity(0.88)))
                }
            }
                .frame(width: 56, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scalesWhenPressed: !isPlayPause))
        .accessibilityLabel(label).help(label)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DynanotchHardwareTransport"))) { notification in
            guard let code = notification.object as? Int else { return }
            if (symbol == "forward.fill" && [17, 19].contains(code))
                || (symbol == "backward.fill" && [18, 20].contains(code)) { skipTrigger &+= 1 }
        }
    }
    private var symbolTransition: ContentTransition {
        reduceMotion ? .identity : symbolReplaceTransition
    }
}

struct SeekBar: View {
    static let remainingTimeWidth: CGFloat = 39

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: NotchModel
    var item: MediaSnapshot
    var tint: Color? = nil
    @State private var previewRatio: Double = 0
    @State private var scrubTrack: TrackIdentity?
    @State private var hover = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let position = model.scrubbing ? previewRatio * item.duration : item.currentPosition
            let ratio = item.duration > 0 ? unit(position / item.duration) : 0
            HStack(spacing: 10) {
                Text(item.duration > 0 ? clockText(position) : "–:––")
                    .contentTransition(.identity).frame(width: 34, alignment: .leading).themed("elapsed")
                GeometryReader { geometry in
                    let engaged = hover || model.scrubbing
                    let trackHeight: CGFloat = engaged ? 6 : 4
                    ZStack(alignment: .leading) {
                        NotchProgressTrack(level: ratio, tint: tint ?? model.accent, backgroundOpacity: 0.18)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.accent)
                        Circle().fill(.white)
                            .frame(width: trackHeight, height: trackHeight)
                            .offset(x: max(0, min(geometry.size.width - trackHeight, geometry.size.width * ratio - trackHeight / 2)))
                            .opacity(engaged ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                    .frame(height: trackHeight)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: engaged)
                    .frame(height: geometry.size.height)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard item.duration > 0, geometry.size.width > 0 else { return }
                        if scrubTrack == nil { scrubTrack = item.identity }
                        previewRatio = unit(value.location.x / geometry.size.width)
                        model.scrubbing = true
                    }.onEnded { value in
                        if let track = scrubTrack, geometry.size.width > 0 {
                            model.media.seek(unit(value.location.x / geometry.size.width), on: track)
                        }
                        scrubTrack = nil
                        model.finishScrubbing()
                    })
                    .onHover { hover = $0 }
                    .accessibilityLabel("Playback position")
                    .accessibilityValue(clockText(position))
                    .accessibilityAdjustableAction { direction in
                        if item.duration > 0 { model.media.seek(unit((position + (direction == .increment ? 5 : -5)) / item.duration), on: item.identity) }
                    }
                }.frame(height: 18)
                Text(item.duration > 0 ? "−" + clockText(max(0, item.duration - position)) : "–:––")
                    .contentTransition(.identity).frame(width: Self.remainingTimeWidth, alignment: .trailing).themed("remaining")
            }.font(.system(size: 22 * model.uiScale, weight: .medium)).monospacedDigit()
                .foregroundStyle(model.theme.color("colors.timeColor", model.theme.flag("glass.enabled", model.preferences.liquidGlass) ? Color.white : Color.notchSecondary))
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
    static let width: CGFloat = 26

    @ObservedObject var model: NotchModel
    var waveform: WaveformService
    var visible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticNotchPreview) private var staticPreview

    var body: some View {
        Group {
            if staticPreview {
                WaveformPreview(waveform: waveform, accent: model.accent,
                                moving: model.media.snapshot?.isPlaying == true && !reduceMotion)
            } else {
                LiveWaveform(waveform: waveform, accent: NSColor(model.theme.element("waveform").color("color", model.accent)), theme: model.theme,
                             playing: model.media.snapshot?.isPlaying == true,
                             visible: visible, reduceMotion: reduceMotion)
            }
        }
        .frame(width: model.theme.element("waveform").number("width", Self.width), height: model.theme.element("waveform").number("height", 26))
        .accessibilityHidden(true)
        .help("Live system audio waveform")
    }
}

private struct WaveformPreview: View {
    @ObservedObject var waveform: WaveformService
    var accent: Color
    var moving: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<6) { i in
                let level = moving && waveform.active ? waveform.levels[i] : 0
                Capsule().fill(accent)
                    .frame(width: 2.2, height: 3 + 22 * level)
            }
        }
    }
}

/// Audio frames change only six layer bounds, independently of the SwiftUI layout.
private struct LiveWaveform: NSViewRepresentable {
    var waveform: WaveformService
    var accent: NSColor
    var theme: NotchTheme
    var playing: Bool
    var visible: Bool
    var reduceMotion: Bool

    func makeNSView(context: Context) -> WaveformLayerView {
        WaveformLayerView(waveform: waveform)
    }

    func updateNSView(_ view: WaveformLayerView, context: Context) {
        view.configure(theme)
        view.update(accent: accent, moving: playing && visible && !reduceMotion, animate: visible && !reduceMotion)
    }
}

@MainActor private final class WaveformLayerView: NSView {
    private var bars = (0..<6).map { _ in CALayer() }
    private var style = NotchTheme()
    func configure(_ theme: NotchTheme) {
        style = theme
        let count = max(1, min(24, Int(theme.number("layout.waveformBars", 6))))
        if bars.count != count {
            bars.forEach { $0.removeFromSuperlayer() }
            bars = (0..<count).map { _ in let bar = CALayer(); bar.backgroundColor = color; layer?.addSublayer(bar); return bar }
        }
        layoutBars()
    }
    override func layout() { super.layout(); layoutBars() }
    private func layoutBars() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let width = max(0.5, min(30, style.number("layout.waveformBarWidth", 2.2)))
        let spacing = max(0, min(30, style.number("layout.waveformBarSpacing", 2)))
        for (index, bar) in bars.enumerated() {
            bar.bounds.size.width = width
            bar.position = CGPoint(x: bounds.midX + (CGFloat(index) - CGFloat(bars.count-1)/2) * (width + spacing), y: bounds.midY)
            bar.cornerRadius = max(0, style.number("layout.waveformCornerRadius", 1.1))
        }
        CATransaction.commit()
    }
    private let waveform: WaveformService
    private var subscription: AnyCancellable?
    private var moving = false
    private var animatesChanges = false
    private var color: CGColor?

    init(waveform: WaveformService) {
        self.waveform = waveform
        super.init(frame: .zero)
        wantsLayer = true
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: 2.2, height: 3)
            bar.position = CGPoint(x: WaveformView.width / 2 + (CGFloat(index) - 2.5) * 4.2, y: 13)
            bar.cornerRadius = 1.1
            layer?.addSublayer(bar)
        }
        subscription = waveform.$levels.sink { [weak self] levels in
            guard let self, self.moving else { return }
            self.setLevels(levels, settle: !self.waveform.active && self.animatesChanges)
        }
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(accent: NSColor, moving: Bool, animate: Bool) {
        animatesChanges = animate
        let nextColor = accent.cgColor
        if color != nextColor {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for bar in bars {
                let previous = bar.presentation()?.backgroundColor ?? color
                bar.backgroundColor = nextColor
                if animate, let previous {
                    let change = CABasicAnimation(keyPath: "backgroundColor")
                    change.fromValue = previous
                    change.duration = 0.3
                    change.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    bar.add(change, forKey: "accent")
                } else {
                    bar.removeAnimation(forKey: "accent")
                }
            }
            CATransaction.commit()
            color = nextColor
        }
        if self.moving != moving {
            self.moving = moving
            if moving {
                for bar in bars { bar.removeAnimation(forKey: "settle") }
            }
            setLevels(moving ? waveform.levels : [], settle: !moving && animate)
        }
        if !animate {
            for bar in bars { bar.removeAllAnimations() }
        }
    }

    private func setLevels(_ levels: [Double], settle: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let source = levels.isEmpty ? 0 : min(levels.count-1, index * levels.count / bars.count)
            let minimum = max(0, style.number("layout.waveformMinHeight", 3))
            let maximum = max(minimum, style.number("layout.waveformMaxHeight", 25))
            let height = minimum + (maximum-minimum) * (levels.isEmpty ? 0 : levels[source])
            guard bar.bounds.height != height else { continue }
            let previous = settle ? bar.presentation()?.bounds ?? bar.bounds : nil
            bar.bounds.size.height = height
            if let previous, previous.height != height {
                let change = CABasicAnimation(keyPath: "bounds")
                change.fromValue = NSValue(rect: previous)
                change.duration = 0.15
                change.timingFunction = CAMediaTimingFunction(name: .easeOut)
                bar.add(change, forKey: "settle")
            }
        }
        CATransaction.commit()
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

private struct PowerBatteryGlyph: View {
    var kind: NoticeKind
    var level: Double?
    var size: CGFloat = 28
    @Environment(\.notchTheme) private var theme

    var body: some View {
        let critical = kind == .batteryCritical || (level.map { $0 <= 0.05 } ?? false)
        let tint: Color = critical ? .red : kind == .batteryLow ? .orange : .green
        let track = kind == .charging && !critical ? tint.opacity(0.22) : Color.white.opacity(0.32)
        let symbol = kind == .charging ? theme.string("symbols.charging", "battery.100percent.bolt") : "battery.100percent"
        let icon = Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
        icon.foregroundStyle(track)
            .overlay {
                if let level {
                    BatteryFill(level: level) { fill in
                        icon.foregroundStyle(tint)
                            .mask(alignment: .leading) {
                                GeometryReader { geometry in
                                    let width = geometry.size.width
                                    // Skip the symbol's side bearing and keep a small
                                    // visible sliver on its rounded leading edge.
                                    let inset = min(size * 0.09, width / 8)
                                    let visibleFill = max(size * 0.075, (width - inset) * fill)
                                    Rectangle().frame(width: fill > 0 ? min(width, inset + visibleFill) : 0)
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
    var detailsOnly = false
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
        if detailsOnly {
            AirPodsBatteryMorph(progress: 1, components: components, lighting: model.airPodsPillLighting,
                               prefersLiquidGlass: model.preferences.liquidGlass, staticPreview: staticPreview, compact: compact)
        } else {
        Button {
            model.toggleAirPodsDetails(notice.id)
        } label: {
            AirPodsBatteryMorph(progress: expanded ? 1 : 0, components: components,
                               lighting: model.airPodsPillLighting, prefersLiquidGlass: model.preferences.liquidGlass,
                               staticPreview: staticPreview,
                               compact: compact)
                .animation(reduceMotion || staticPreview ? nil : IslandMotion.satellite, value: expanded)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(notice.name) battery details")
        .accessibilityValue(expanded
            ? components.map { "\($0.label): \($0.reading)" }.joined(separator: ", ")
            : notice.battery.map { "\(Int(($0 * 100).rounded())) percent" } ?? "Battery level unavailable")
        .accessibilityHint(expanded ? "Collapse battery details" : "Expand battery details")
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
            candidate = artwork?.family == .airpodsPro ? "airpodpro.left"
                : ([8217, 8219, 8240, 8242, 8246, 8247].contains(artwork?.productID ?? 0) ? "airpod.gen4.left" : "airpod.gen3.left")
        case .right:
            fallback = "airpod.right"
            candidate = artwork?.family == .airpodsPro ? "airpodpro.right"
                : ([8217, 8219, 8240, 8242, 8246, 8247].contains(artwork?.productID ?? 0) ? "airpod.gen4.right" : "airpod.gen3.right")
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
        let modernFallback = part == .left ? "airpod.gen3.left" : part == .right ? "airpod.gen3.right" : fallback
        let automatic = (usesModernSymbols ? [candidate, modernFallback, fallback] : [fallback])
            .first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? fallback
        return model.theme.string(part == .chargingCase ? "symbols.airPodsCase" : part == .left ? "symbols.airPodLeft" : "symbols.airPodRight", automatic)
    }

}

private struct AirPodsBatteryComponent {
    var label: String
    var symbol: String
    var level: Double?
    var reading: String { level.map { "\(Int(($0 * 100).rounded()))%" } ?? "Unavailable" }
}

private struct AirPodsBatteryMorph<Compact: View>: View, Animatable {
    @Environment(\.notchTheme) private var theme
    var progress: Double
    var components: [AirPodsBatteryComponent]
    var lighting: EdgeLighting
    var prefersLiquidGlass: Bool
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
            Capsule().fill(theme.element("airpods.details").color("backgroundColor", .notchSurface))
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
                        .frame(width: height - 6, height: height - 6)
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
        .overlay(alignment: .trailing) {
            compact().frame(width: height, height: height)
                .opacity(compactOpacity)
                .allowsHitTesting(false)
        }
        .clipShape(Capsule())
        .overlay {
            ThemedBubbleRim(shape: Capsule(), lighting: lighting,
                            prefersLiquidGlass: prefersLiquidGlass, staticPreview: staticPreview)
        }
        .contentShape(Capsule())
        .themed("airpods.details")
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
                           loops: model.heldAirPodsNotice == notice.id,
                           onPlaybackReady: { model.airPodsMovieReady(notice.id, duration: $0) },
                           onPlaybackEnd: { model.airPodsMovieEnded(notice.id) },
                           onPlaybackFailure: { model.airPodsMovieFailed(notice.id) })
    }
}

struct InlineNoticeView: View {
    private static let powerIconSize: CGFloat = 24
    private static let powerIconWidth: CGFloat = 48
    private static let percentageSize: CGFloat = 14
    private static let powerSpacing: CGFloat = 8
    private static let percentageWidth = ceil(("100%" as NSString).size(withAttributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: percentageSize, weight: .semibold)
    ]).width) + 2

    static func powerTrailingWidth(hasPercentage: Bool) -> CGFloat {
        powerIconWidth + (hasPercentage ? percentageWidth + powerSpacing : 0)
    }

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
                    HStack(spacing: Self.powerSpacing) {
                        if let battery = notice.battery {
                            Text("\(Int((battery * 100).rounded()))%")
                                .font(.system(size: Self.percentageSize, weight: .semibold))
                                .monospacedDigit()
                                .fixedSize()
                                .frame(width: Self.percentageWidth, alignment: .trailing)
                        }
                        PowerBatteryGlyph(kind: notice.kind, level: notice.battery, size: Self.powerIconSize)
                            .id(notice.id)
                            .frame(width: Self.powerIconWidth)
                    }.foregroundStyle(color)
                } else if model.showsInlineAirPodsDetails, notice.airPodsArtwork != nil {
                    AirPodsBatterySatellite(notice: notice, model: model, system: model.system, detailsOnly: true) { Color.clear }
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
    var scalesWhenPressed = true

    func makeBody(configuration: Configuration) -> some View {
        if scalesWhenPressed {
            configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
        } else {
            configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
        }
    }
}

/// Fade the edges where the scrolling title extends past its viewport.
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
                let offset = canScroll ? CGFloat(frame.offset) : 0
                let fadeLeading = canScroll && (frame.fadedEdges || offset < -0.5)
                let fadeTrailing = canScroll && (frame.fadedEdges || offset > -overflow + 0.5)
                if reduceMotion {
                    Text(text).font(font).foregroundStyle(color)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 36) {
                        Text(text).font(font).foregroundStyle(color).fixedSize().background {
                            GeometryReader { size in
                                Color.clear.onAppear { textWidth = size.size.width }
                                    .notchOnChange(of: size.size.width) { _, width in textWidth = width; start = Date() }
                            }
                        }
                        if canScroll { Text(text).font(font).foregroundStyle(color).fixedSize().accessibilityHidden(true) }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset)
                    .frame(width: geometry.size.width, alignment: .leading)
                    .mask {
                        HStack(spacing: 0) {
                            LinearGradient(colors: [.white.opacity(fadeLeading ? 0 : 1), .white], startPoint: .leading, endPoint: .trailing)
                                .frame(width: min(12, geometry.size.width / 4))
                            Color.white
                            LinearGradient(colors: [.white, .white.opacity(fadeTrailing ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                                .frame(width: min(12, geometry.size.width / 4))
                        }
                        .animation(.easeInOut(duration: 0.22), value: fadeLeading)
                        .animation(.easeInOut(duration: 0.22), value: fadeTrailing)
                    }
                }
            }
            .notchOnChange(of: geometry.size.width) { _, _ in start = Date() }
        }.frame(height: 19).clipped().accessibilityLabel(text).notchOnChange(of: text) { _, _ in start = Date() }
    }
}

struct ProgressBarVisualCheck: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach([0.0, 0.001, 1.0 / 64, 2.0 / 64, 1.0 / 16, 2.0 / 16, 0.5, 1.0], id: \.self) { level in
                HStack(spacing: 24) {
                    Text(String(format: "%.1f%%", level * 100)).monospacedDigit().frame(width: 64, alignment: .trailing)
                    NotchVolumeBar(osd: .init(kind: .volume, level: level, muted: false))
                    NotchProgressTrack(level: level, tint: .cyan).frame(width: 220, height: 4)
                }
            }
        }.padding(30).background(.black).foregroundStyle(.white)
    }
}
