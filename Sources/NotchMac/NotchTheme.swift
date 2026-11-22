import AppKit
import SwiftUI
import Combine
import NotchCore

struct NotchTheme {
    var values: [String: Any] = [:]
    func value(_ path: String) -> Any? {
        path.split(separator: ".").reduce(values as Any?) { result, key in (result as? [String: Any])?[String(key)] }
    }
    func number(_ path: String, _ fallback: Double) -> Double {
        guard let n = value(path) as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return fallback }
        return n.doubleValue
    }
    func element(_ name: String) -> NotchTheme { NotchTheme(values: (values["elements"] as? [String: Any])?[name] as? [String: Any] ?? [:]) }
    func flag(_ path: String, _ fallback: Bool) -> Bool { value(path) as? Bool ?? fallback }
    func string(_ path: String, _ fallback: String) -> String { value(path) as? String ?? fallback }
    func color(_ path: String, _ fallback: Color) -> Color {
        guard let raw = value(path) as? String else { return fallback }
        return Self.hex(raw) ?? fallback
    }
    static func hex(_ raw: String) -> Color? {
        let text = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard [6, 8].contains(text.count), let n = UInt64(text, radix: 16) else { return nil }
        let rgba = text.count == 6 ? (n << 8) | 255 : n
        return Color(.sRGB, red: Double((rgba >> 24) & 255)/255,
                     green: Double((rgba >> 16) & 255)/255, blue: Double((rgba >> 8) & 255)/255,
                     opacity: Double(rgba & 255)/255)
    }
    static func merge(_ base: [String: Any], _ overlay: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overlay {
            if let child = value as? [String: Any] { result[key] = merge(result[key] as? [String: Any] ?? [:], child) }
            else { result[key] = value }
        }
        return result
    }
}

/// Measurements shared by the notch and its controls. The legacy layout and
/// surface keys still supply defaults when a design token is absent.
struct NotchDesign {
    let theme: NotchTheme

    private enum Metric: String, CaseIterable {
        case basePadding, smallPadding, mediumPadding, largePadding
        case horizontalSpacing, verticalSpacing, controlSpacing, satelliteSpacing
        case compactRadius, peekRadius, expandedRadius, innerRadius

        var maximum: Double {
            switch self {
            case .compactRadius, .peekRadius, .expandedRadius, .innerRadius: return 100
            case .satelliteSpacing: return 80
            default: return 48
            }
        }
    }

    static var schema: [String: Any] {
        Dictionary(uniqueKeysWithValues: Metric.allCases.map { ($0.rawValue, NSNull()) })
    }

    static func validate(_ theme: NotchTheme) throws {
        for metric in Metric.allCases {
            guard let value = theme.value("design." + metric.rawValue) as? NSNumber else { continue }
            if CFGetTypeID(value) == CFBooleanGetTypeID() || !(0...metric.maximum).contains(value.doubleValue) {
                throw NSError(domain: "Theme", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "design.\(metric.rawValue) must be between 0 and \(Int(metric.maximum))."
                ])
            }
        }
    }

    private func value(_ metric: Metric, fallback: Double) -> CGFloat {
        min(metric.maximum, max(0, theme.number("design." + metric.rawValue, fallback)))
    }

    private var base: CGFloat { value(.basePadding, fallback: 12) }
    var small: CGFloat { value(.smallPadding, fallback: base * 2 / 3) }
    var medium: CGFloat { value(.mediumPadding, fallback: base * 1.5) }
    var large: CGFloat { value(.largePadding, fallback: base * 2) }
    private func legacyPadding(_ key: String, fallback: CGFloat) -> CGFloat {
        theme.value("design.basePadding") is NSNumber ? fallback : theme.number(key, fallback)
    }

    var popoverPadding: CGFloat { base }
    var headerPadding: CGFloat { value(.mediumPadding, fallback: legacyPadding("layout.headerPadding", fallback: medium)) }
    var headerTop: CGFloat { value(.smallPadding, fallback: legacyPadding("layout.headerTop", fallback: small)) }
    var progressPadding: CGFloat { value(.largePadding, fallback: legacyPadding("layout.progressPadding", fallback: large)) }
    var controlsPadding: CGFloat { value(.largePadding, fallback: legacyPadding("layout.controlsPadding", fallback: large)) }
    var horizontalSpacing: CGFloat { value(.horizontalSpacing, fallback: theme.number("layout.headerSpacing", 10)) }
    var verticalSpacing: CGFloat { value(.verticalSpacing, fallback: theme.number("layout.metadataSpacing", 6)) }
    var osdTrailingInset: CGFloat { min(small / 2, 6) }
    private var osdSpacing: CGFloat { value(.horizontalSpacing, fallback: 6) }
    var controlSpacing: CGFloat { value(.controlSpacing, fallback: theme.number("layout.controlsSpacing", 7)) }
    var satelliteSpacing: CGFloat { max(2, value(.satelliteSpacing, fallback: theme.number("layout.bubbleGap", 8))) }
    var innerRadius: CGFloat { value(.innerRadius, fallback: 10) }

    struct OSDLayout {
        let iconSize: CGFloat
        let iconCenter: CGPoint
        let barWidth: CGFloat
        let barCenter: CGPoint
        let percentageWidth: CGFloat
        let percentageCenter: CGPoint
        static let barHeight: CGFloat = 5
        static let percentageFontSize: CGFloat = 11
    }

    private func osdIconSize(hasNotch: Bool) -> CGFloat { hasNotch ? 24 : 20 }

    func osdWidth(cameraWidth: CGFloat, hasNotch: Bool, wingWidth: CGFloat) -> CGFloat {
        hasNotch ? cameraWidth + 2 * (wingWidth + small + osdSpacing) : 112
    }

    func osdHeight(cameraHeight: CGFloat, hasNotch: Bool) -> CGFloat {
        guard hasNotch else { return 31 }
        let iconHalfHeight = osdIconSize(hasNotch: true) * 1.25 / 2
        return cameraHeight + OSDLayout.barHeight / 2 + iconHalfHeight + min(small, 12)
    }

    func osdLayout(width: CGFloat, cameraHeight: CGFloat, hasNotch: Bool, wingLimit: CGFloat) -> OSDLayout {
        let sidePadding = min(small, width * (hasNotch ? 0.1 : 0.055))
        let innerWidth = max(1, width - 2 * sidePadding)
        let wing = min(wingLimit, innerWidth * 0.31)
        let gap = min(osdSpacing, innerWidth / 8)
        let rowY = hasNotch
            ? cameraHeight + OSDLayout.barHeight / 2
            : osdHeight(cameraHeight: cameraHeight, hasNotch: false) / 2
        return OSDLayout(iconSize: osdIconSize(hasNotch: hasNotch),
                         iconCenter: CGPoint(x: sidePadding + wing / 2, y: rowY),
                         barWidth: max(1, innerWidth - 2 * (wing + gap)),
                         barCenter: CGPoint(x: width / 2, y: rowY),
                         percentageWidth: wing,
                         percentageCenter: CGPoint(x: width - sidePadding - wing / 2, y: rowY))
    }

    func outerRadius(for presentation: Presentation) -> CGFloat {
        switch presentation {
        case .expanded: return value(.expandedRadius, fallback: 30)
        case .peek: return value(.peekRadius, fallback: 24)
        default: return value(.compactRadius, fallback: 12)
        }
    }

    static func concentricRadius(outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(0, outer - max(0, padding))
    }
}

@MainActor final class NotchThemeStore: ObservableObject {
    static let shared = NotchThemeStore()
    static let states = ["idle", "collapsed", "expanded", "peek", "notice", "osd", "airpods", "charging", "volume", "brightness", "browser", "locked", "unlocking", "notchless"]
    static let elementNames = ["surface", "artwork", "title", "artist", "metadata", "waveform", "progress",
        "elapsed", "remaining", "controls", "previous", "playPause", "next", "favorite", "airplay", "notice",
        "osd", "bubble.music", "bubble.lock", "bubble.airpods", "bubble.charging", "bubble.volume", "airpods.details"]
    @Published private(set) var revision = 0
    @Published private(set) var error = ""
    let folder: URL
    private var documents: [String: [String: Any]] = [:]
    private var cache: [String: NotchTheme] = [:]
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var reloadWork: DispatchWorkItem?

    init(folder: URL? = nil, watch: Bool = true) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dynanotch/Themes", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
            var files = ["global": Self.defaults]
            for state in Self.states { files[state] = ["version": 1, "description": "Overrides global.json for \(state). Null restores the built-in value."] }
            for (name, value) in files {
                let url = self.folder.appendingPathComponent(name + ".json")
                if !FileManager.default.fileExists(atPath: url.path) {
                    let bundled = Bundle.main.resourceURL?.appendingPathComponent("Themes/" + name + ".json")
                    let data: Data
                    if let bundledData = bundled.flatMap({ try? Data(contentsOf: $0) }) { data = bundledData }
                    else { data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) }
                    try data.write(to: url, options: .atomic)
                }
            }
        } catch { self.error = error.localizedDescription }
        writeReference()
        reload()
        if watch { installWatchers() }
    }
    private func writeReference() {
        let reference: [String: Any] = [
            "formatVersion": 1,
            "editing": "Save UTF-8 JSON. Files reload automatically. If any file is invalid, the entire last working theme stays active; Settings shows the filename and error. Null restores the built-in value; omit a field to inherit it.",
            "inheritance": ["global.json", "presentation state", "browser/device/OSD variant", "unlocking", "locked"],
            "files": ["global.json"] + Self.states.map { $0 + ".json" },
            "units": "Positions and sizes are points. Colors use #RRGGBB or #RRGGBBAA. Opacity is 0–1. Surface width includes the camera clearance; height cannot be smaller than the physical notch.",
            "elements": Self.elementNames,
            "elementOptions": ["visible", "opacity", "offsetX", "offsetY", "scale", "rotation", "width", "height", "padding", "fontSize", "fontWeight", "color", "backgroundColor", "cornerRadius", "shadowColor", "shadowRadius", "shadowX", "shadowY", "glyphWidth", "glyphHeight"],
            "design": "Optional shared tokens: basePadding, smallPadding, mediumPadding, largePadding, horizontalSpacing, verticalSpacing, controlSpacing, satelliteSpacing, compactRadius, peekRadius, expandedRadius, and innerRadius. Explicit tokens override corresponding legacy layout keys; surface.radius still overrides the selected outer radius. Omit or set a token to null to use legacy layout and defaults.",
            "symbols": "Map symbol names to SF Symbols strings; null keeps the native automatic symbol/vector animation. Available names are listed in global.json.",
            "layout": "surface controls the animated outline. layout controls intrinsic artwork placement, text/transport spacing, progress padding, bubbles, and waveform bar geometry. elements applies final per-part transforms. Custom layers are noninteractive decoration inside the notch and never alter playback actions.",
            "motion": "response/damping drives the interruptible surface spring. bubbleResponse/bubbleDamping drives satellites. fadeDuration controls content fading. Reduce Motion and Reduce Transparency remain respected.",
            "expandedExample": ["version": 1, "surface": ["width": 430, "radius": 36],
                "glass": ["refraction": 28, "lensHeight": 40, "dimming": 0.2],
                "elements": ["title": ["fontSize": 17, "color": "#FFFFFFFF"], "next": ["scale": 1.1]],
                "layout": ["controlsSpacing": 10]],
            "collapsedExample": ["version": 1, "surface": ["hoverWidth": 8, "hoverHeight": 2], "layout": ["bubbleSize": 30]],
            "layerExamples": [["text": "{title}", "x": 20, "y": 80, "width": 250, "height": 24, "fontSize": 14, "color": "#FFFFFFFF"],
                ["symbol": "sparkles", "x": 280, "y": 60, "width": 20, "height": 20, "color": "#FFD700FF"]],
            "insetLayers": "A shape layer with surfaceInset follows the current surface bounds. Its corner radius is the outer radius minus the inset, clamped to zero.",
            "layerFields": ["surfaceInset", "text", "symbol", "color", "x", "y", "width", "height", "fontSize", "cornerRadius", "rotation", "opacity"],
            "bindings": ["{title}", "{artist}", "{elapsed}", "{remaining}", "{battery}", "{volume}", "{brightness}", "{device}"],
            "reset": "Restore the bundled JSON templates or remove the edited files and relaunch Dynanotch. Your preferences, permissions, and media integrations are separate from theme files."
        ]
        let url = folder.appendingPathComponent("REFERENCE.json")
        if let data = try? JSONSerialization.data(withJSONObject: reference, options: [.prettyPrinted, .sortedKeys]),
           (try? Data(contentsOf: url)) != data {
            try? data.write(to: url, options: .atomic)
        }
    }
    func theme(state: String, variants: [String] = [], locked: Bool = false) -> NotchTheme {
        let key = ([state] + variants + [locked ? "locked" : "unlocked"]).joined(separator: "/")
        if let cached = cache[key] { return cached }
        var values = NotchTheme.merge(documents["global"] ?? [:], documents[state] ?? [:])
        for variant in variants { values = NotchTheme.merge(values, documents[variant] ?? [:]) }
        if locked { values = NotchTheme.merge(values, documents["locked"] ?? [:]) }
        let result = NotchTheme(values: values)
        cache[key] = result
        return result
    }
    func reload() {
        do {
            var next: [String: [String: Any]] = [:]
            for name in ["global"] + Self.states {
                do {
                    let data = try Data(contentsOf: folder.appendingPathComponent(name + ".json"))
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw NSError(domain: "Theme", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected a JSON object."])
                    }
                    try Self.validate(object)
                    next[name] = object
                } catch { throw NSError(domain: "Theme", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name).json: \(error.localizedDescription)"] ) }
            }
            documents = next; cache = [:]; error = ""; revision &+= 1
        } catch { self.error = error.localizedDescription }
    }
    var globalTheme: NotchTheme { NotchTheme(values: documents["global"] ?? [:]) }

    func setGlobalThemeValues(_ changes: [String: [String: Any]]) {
        let url = folder.appendingPathComponent("global.json")
        do {
            let data = try Data(contentsOf: url)
            guard let current = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "Theme", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected a JSON object."])
            }
            let updated = NotchTheme.merge(current, changes)
            try Self.validate(updated)
            try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
            documents["global"] = updated
            cache.removeAll()
            revision &+= 1
        } catch {
            self.error = "global.json: \(error.localizedDescription)"
        }
    }

    func openFolder() { NSWorkspace.shared.open(folder) }
    private func installWatchers() {
        watchers.forEach { $0.cancel() }; watchers = []
        for url in [folder] + (["global"] + Self.states).map({ folder.appendingPathComponent($0 + ".json") }) {
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.reloadWork?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.reload(); self?.installWatchers() }
                self.reloadWork = work
                DispatchQueue.main.asyncAfter(deadline: .now()+0.25, execute: work)
            }
            source.setCancelHandler { close(fd) }; source.resume(); watchers.append(source)
        }
    }
    static func validate(_ object: [String: Any]) throws {
        func fail(_ message: String) throws { throw NSError(domain: "Theme", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        if let version = object["version"] as? Int, version != 1 { try fail("Unsupported theme version \(version).") }
        func walk(_ value: Any, path: String) throws {
            if let dict = value as? [String: Any] {
                for (key, child) in dict { try walk(child, path: path.isEmpty ? key : path + "." + key) }
            } else if let list = value as? [Any] { for child in list { try walk(child, path: path) } }
            else if let n = value as? NSNumber, !n.doubleValue.isFinite { try fail("\(path) must be finite.") }
            if let string = value as? String, path.lowercased().contains("color"), NotchTheme.hex(string) == nil {
                try fail("\(path): expected #RRGGBB or #RRGGBBAA.")
            }
        }
        func types(_ input: [String: Any], _ schema: [String: Any], _ prefix: String) throws {
            for (key, value) in input {
                if value is NSNull { continue }
                let path = prefix.isEmpty ? key : prefix + "." + key
                guard let expected = schema[key] else { continue }
                if let child = expected as? [String: Any] {
                    guard let actual = value as? [String: Any] else { try fail("\(path) must be an object."); continue }
                    try types(actual, child, path)
                } else if let number = expected as? NSNumber {
                    let boolean = CFGetTypeID(number) == CFBooleanGetTypeID()
                    guard let actual = value as? NSNumber,
                          (CFGetTypeID(actual) == CFBooleanGetTypeID()) == boolean else {
                        try fail("\(path) must be a \(boolean ? "boolean" : "number")."); continue
                    }
                } else if expected is String {
                    if !(value is String) { try fail("\(path) must be a string.") }
                } else if expected is NSNull {
                    if path.lowercased().contains("color") || path.hasPrefix("symbols.") {
                        if !(value is String) { try fail("\(path) must be a hex color or null.") }
                    } else if !(value is NSNumber) { try fail("\(path) must be a number or null.") }
                }
            }
        }
        try types(object, defaults, "")
        try walk(object, path: "")
        try NotchDesign.validate(NotchTheme(values: object))
        for key in ["surface", "glass", "motion", "layout", "elements", "colors", "design"] {
            if let value = object[key], !(value is [String: Any]) { try fail("\(key) must be an object.") }
        }
        for layer in object["layers"] as? [[String: Any]] ?? [] {
            if let inset = layer["surfaceInset"], !(inset is NSNull) {
                guard let number = inset as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      (0...100).contains(number.doubleValue) else { try fail("layers.surfaceInset must be between 0 and 100."); continue }
            }
        }
        if let elements = object["elements"] as? [String: Any] {
            for (name, element) in elements where !(element is [String: Any]) { try fail("elements.\(name) must be an object.") }
        }
    }
    static var defaults: [String: Any] {
        let nullable = NSNull()
        var elements: [String: Any] = [:]
        for name in elementNames {
            elements[name] = ["visible": true, "opacity": 1, "offsetX": 0, "offsetY": 0, "scale": 1,
                "rotation": 0, "width": nullable, "height": nullable, "fontSize": nullable, "fontWeight": "regular",
                "color": nullable, "backgroundColor": nullable, "cornerRadius": 0, "padding": 0,
                "shadowColor": "#00000000", "shadowRadius": 0, "shadowX": 0, "shadowY": 0] as [String: Any]
        }
        return ["version": 1, "description": "State files override these values. Elements use points; colors are hex RGBA. Edit and save to reload automatically. Null retains the built-in size/color. Names containing dots are literal element names.",
            "surface": ["width": nullable, "height": nullable, "offsetX": nullable, "radius": nullable, "earRadius": nullable,
                "backgroundColor": "#000000", "shadowOpacity": 0.32, "shadowRadius": 15, "shadowX": 0, "shadowY": 6,
                "edgeHighlight": true, "edgeHighlightIntensity": 1, "hoverWidth": 6, "hoverHeight": 2],
            "glass": ["enabled": nullable, "refraction": 32, "lensHeight": 44, "dispersion": 0.35, "blur": 0,
                "dimming": 0.25, "fadeHeight": 90, "topOpacity": 1, "edgeHighlight": false, "edgeHighlightIntensity": 1, "shadowOpacity": 0],
            "colors": ["accentColor": nullable, "secondaryColor": "#9EA1B0", "timeColor": nullable],
            "layout": ["artworkSize": nullable, "artworkX": nullable, "artworkY": nullable, "artworkRadius": nullable,
                "waveformInset": nullable, "waveformY": nullable, "headerSpacing": 10, "metadataSpacing": 6,
                "headerPadding": 18, "headerTop": 8, "metadataY": -7, "controlsSpacing": 7,
                "controlsTop": 2, "controlsPadding": 24, "progressTop": 2, "progressPadding": 24,
                "notchlessScale": 0.85, "notchlessTopInset": 6, "idlePillWidth": 64, "idlePillSeconds": 5, "idleShrinkSeconds": 1.2,
                "bubbleSize": 32, "bubbleGap": 8, "airPodsExpandedWidth": 204,
                "waveformBars": 6, "waveformBarWidth": 2.2, "waveformBarSpacing": 2,
                "waveformMinHeight": 3, "waveformMaxHeight": 25, "waveformCornerRadius": 1.1],
            "motion": ["response": 0.32, "idleShrinkResponse": 0.65, "damping": 0.88, "bubbleResponse": 0.57, "bubbleDamping": 0.94,
                "fadeDuration": 0.14],
            "symbols": Dictionary(uniqueKeysWithValues: ["previous", "next", "play", "pause", "favorite", "favorited", "airplay", "locked", "unlocked", "volume", "muted", "brightness", "charging", "airPodsCase", "airPodLeft", "airPodRight"].map { ($0, nullable as Any) }),
            "elements": elements, "layers": [], "design": NotchDesign.schema]
    }
}

private struct NotchThemeKey: EnvironmentKey { static let defaultValue = NotchTheme() }
extension EnvironmentValues { var notchTheme: NotchTheme { get { self[NotchThemeKey.self] } set { self[NotchThemeKey.self] = newValue } } }

extension View {
    func themed(_ name: String) -> some View { modifier(NotchElementTheme(name: name)) }
}
private struct NotchElementTheme: ViewModifier {
    var name: String
    @Environment(\.notchTheme) private var theme
    func body(content: Content) -> some View {
        let element = NotchTheme(values: theme.values["elements"] as? [String: Any] ?? [:])
        let config = NotchTheme(values: element.values[name] as? [String: Any] ?? [:])
        let width = (config.value("width") as? NSNumber).map { CGFloat(max(0, min(2000, $0.doubleValue))) }
        let height = (config.value("height") as? NSNumber).map { CGFloat(max(0, min(2000, $0.doubleValue))) }
        return content
            .frame(width: width, height: height)
            .padding(max(0, min(100, config.number("padding", 0))))
            .background(config.color("backgroundColor", .clear), in: RoundedRectangle(cornerRadius: max(0, config.number("cornerRadius", 0))))
            .modifier(ThemeForeground(color: NotchTheme.hex(config.string("color", ""))))
            .modifier(ThemeFont(size: (config.value("fontSize") as? NSNumber)?.doubleValue, weight: config.string("fontWeight", "regular")))
            .scaleEffect(max(0.01, min(5, config.number("scale", 1))))
            .rotationEffect(.degrees(config.number("rotation", 0)))
            .offset(x: config.number("offsetX", 0), y: config.number("offsetY", 0))
            .opacity(config.flag("visible", true) ? max(0, min(1, config.number("opacity", 1))) : 0)
            .allowsHitTesting(config.flag("visible", true) && config.number("opacity", 1) > 0)
            .accessibilityHidden(!config.flag("visible", true))
            .shadow(color: config.color("shadowColor", .clear), radius: max(0, config.number("shadowRadius", 0)),
                    x: config.number("shadowX", 0), y: config.number("shadowY", 0))
    }
}
private struct ThemeForeground: ViewModifier {
    var color: Color?
    @ViewBuilder func body(content: Content) -> some View { if let color { content.foregroundStyle(color) } else { content } }
}
private struct ThemeFont: ViewModifier {
    var size: Double?
    var weight: String
    @ViewBuilder func body(content: Content) -> some View {
        if let size { content.font(.system(size: max(1, min(200, size)), weight: weight == "bold" ? .bold : weight == "semibold" ? .semibold : weight == "light" ? .light : .regular)) }
        else { content }
    }
}

struct NotchThemeLayers: View {
    @Environment(\.notchTheme) private var theme
    var model: NotchModel
    var outerRadius: CGFloat
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array((theme.value("layers") as? [[String: Any]] ?? []).enumerated()), id: \.offset) { _, raw in
                let layer = NotchTheme(values: raw)
                if raw["surfaceInset"] is NSNumber {
                    GeometryReader { geometry in
                        let inset = min(max(0, layer.number("surfaceInset", 0)), min(geometry.size.width, geometry.size.height) / 2)
                        RoundedRectangle(cornerRadius: NotchDesign.concentricRadius(outer: outerRadius, padding: inset))
                            .fill(layer.color("color", .white))
                            .padding(inset)
                            .opacity(layer.number("opacity", 1))
                    }
                } else {
                    Group {
                        if let symbol = raw["symbol"] as? String { Image(systemName: symbol).font(.system(size: layer.number("fontSize", 16))) }
                        else if let text = raw["text"] as? String {
                            Text(text.replacingOccurrences(of: "{title}", with: model.media.snapshot?.identity.title ?? "")
                                .replacingOccurrences(of: "{artist}", with: model.media.snapshot?.identity.artist ?? "")
                                .replacingOccurrences(of: "{elapsed}", with: clockText(model.media.snapshot?.currentPosition ?? 0))
                                .replacingOccurrences(of: "{remaining}", with: clockText(max(0, (model.media.snapshot?.duration ?? 0) - (model.media.snapshot?.currentPosition ?? 0))))
                                .replacingOccurrences(of: "{battery}", with: model.system.state.battery.map { "\(Int($0*100))%" } ?? "—")
                                .replacingOccurrences(of: "{volume}", with: "\(Int(model.audio.volume*100))%")
                                .replacingOccurrences(of: "{brightness}", with: "\(Int(model.brightness.level*100))%")
                                .replacingOccurrences(of: "{device}", with: model.mainNotice?.name ?? ""))
                                .font(.system(size: layer.number("fontSize", 16)))
                        } else { RoundedRectangle(cornerRadius: layer.number("cornerRadius", 0)).fill(layer.color("color", .white)) }
                    }
                    .foregroundStyle(layer.color("color", .white))
                    .frame(width: layer.number("width", 100), height: layer.number("height", 24))
                    .opacity(layer.number("opacity", 1))
                    .rotationEffect(.degrees(layer.number("rotation", 0)))
                    .offset(x: layer.number("x", 0), y: layer.number("y", 0))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
