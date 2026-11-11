import SwiftUI
import ServiceManagement
import AppKit
import NotchCore

struct SettingsView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var waveform: WaveformService
    @ObservedObject var media: MediaService
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError = ""
    @State private var screens = NSScreen.screens

    private enum PreviewDevice: String, CaseIterable {
        case original = "AirPods (1st/2nd gen)"
        case third = "AirPods 3"
        case fourth = "AirPods 4"
        case fifth = "AirPods 5"
        case pro = "AirPods Pro"
        case max = "AirPods Max"

        var artwork: AirPodsArtwork {
            switch self {
            case .original: return .init(family: .airpods)
            case .third: return .init(family: .airpods, productID: 8211)
            // Use the AirPods 4 loop for the AirPods 5 preview.
            case .fourth, .fifth: return .init(family: .airpods, productID: 8217)
            case .pro: return .init(family: .airpodsPro)
            case .max: return .init(family: .airpodsMax)
            }
        }
    }

    @State private var previewDevice: PreviewDevice = .pro
    @State private var previewColor = 0
    @State private var previewBatteryUnavailable = false

    private let maxColors: [(name: String, product: Int, color: Int?)] = [
        ("Default", 8202, nil),
        ("Space Grey (Lightning)", 8202, 15),
        ("Pink (Lightning)", 8202, 2),
        ("Sky Blue (Lightning)", 8202, 3),
        ("Silver (Lightning)", 8202, 16),
        ("Green (Lightning)", 8202, 17),
        ("Midnight (USB-C)", 8223, 18),
        ("Starlight (USB-C)", 8223, 19),
        ("Blue (USB-C)", 8223, 20),
        ("Orange (USB-C)", 8223, 21),
        ("Purple (USB-C)", 8223, 22),
    ]

    var body: some View {
        TabView(selection: $model.settingsTab) {
            general.tabItem { Label("General", systemImage: "slider.horizontal.3") }.tag(NotchModel.SettingsTab.general)
            calibration.tabItem { Label("Calibration", systemImage: "viewfinder") }.tag(NotchModel.SettingsTab.calibration)
            integrations.tabItem { Label("Media & Audio", systemImage: "waveform") }.tag(NotchModel.SettingsTab.media)
        }
        .padding(16).frame(width: 570, height: 480)
        .tint(Color.notchAccent)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = NSScreen.screens }
        .onDisappear { model.calibrating = false }
    }

    private var general: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "macbook.gen2").font(.system(size: 34, weight: .light)).foregroundStyle(Color.notchAccent).frame(width: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dynanotch").font(.system(size: 19, weight: .semibold))
                        Text("Your notch, a little more useful.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
            }
            Section("Appearance & behavior") {
                Toggle("Hide menu-bar icon", isOn: $preferences.hideMenuBarIcon)
                Text("Hover over the notch and press ⌘, to open Settings. Accessibility access is needed when another app is active. Reopening Dynanotch from Applications also opens Settings when the menu icon is hidden.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Expand player on hover", isOn: $preferences.expandOnHover)
                Toggle("Show notch on the lock screen", isOn: $preferences.showOnLockScreen)
                Toggle("Use colors from album artwork", isOn: $preferences.artworkTint)
                Toggle("Device and battery notices", isOn: $preferences.showNotices)
                Toggle("Volume and brightness overlay", isOn: $preferences.showOSD)
                Toggle("Launch at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, value in
                    do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = "" }
                    catch { loginError = "Move the app to Applications, then try again. \(error.localizedDescription)"; launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
                if !loginError.isEmpty { Text(loginError).font(.caption).foregroundStyle(.orange) }
            }
            Section("Try it") {
                Toggle("Preview player", isOn: Binding(get: { model.previewMode }, set: { model.setPreview($0) }))
                HStack {
                    Button("Charging notice", systemImage: "bolt.fill") { model.previewCharging() }
                    Spacer()
                }
                Text("Hover over music to expand it. Use the menu-bar icon or ⌘, over the notch to open Settings.").font(.caption).foregroundStyle(.secondary)
            }
            Section("AirPods connection previews") {
                Picker("Device", selection: $previewDevice) {
                    ForEach(PreviewDevice.allCases, id: \.self) { device in
                        Text(device.rawValue).tag(device)
                    }
                }
                if previewDevice == .max {
                    Picker("Colour", selection: $previewColor) {
                        ForEach(maxColors.indices, id: \.self) { index in
                            Text(maxColors[index].name).tag(index)
                        }
                    }
                }
                Toggle("Simulate unavailable battery", isOn: $previewBatteryUnavailable)
                Button("Preview connection", systemImage: "play.circle") {
                    let variant = maxColors[previewColor]
                    let artwork = previewDevice == .max
                        ? AirPodsArtwork(family: .airpodsMax, productID: variant.product, colorID: variant.color)
                        : previewDevice.artwork
                    model.previewNotice(
                        artwork: artwork,
                        battery: previewBatteryUnavailable ? nil : 0.75
                    )
                }
                .disabled(!preferences.showNotices)
                Text("Sample charge: case 92%, left 68%, right 43%. AirPods Max 81%.")
                    .font(.caption).foregroundStyle(.secondary)
                if !preferences.showNotices {
                    Text("Enable Device and battery notices above to use previews.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Restart Dynanotch", systemImage: "arrow.clockwise") { model.restartApp?() }
                Button("Quit Dynanotch", systemImage: "power") { NSApp.terminate(nil) }
            }
        }.formStyle(.grouped)
    }

    private var calibration: some View {
        Form {
            Section("Display") {
                Picker("Show notch on", selection: $preferences.selectedDisplay) {
                    Text("Automatic · prefer built-in notch").tag(UInt32(0))
                    ForEach(screens, id: \.displayID) { screen in Text(screen.localizedName).tag(screen.displayID) }
                }
                LabeledContent("Detected geometry", value: "\(Int(model.cameraWidth)) × \(Int(model.cameraHeight)) pt")
                Text("The built-in camera cutout is measured automatically. A compact virtual notch is used on displays without a cutout.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Fine-tune") {
                Toggle("Use manual calibration", isOn: $preferences.manualGeometry)
                Toggle("Show calibration guide", isOn: $model.calibrating)
                geometrySlider("Width", value: $preferences.cameraWidth, range: 100...400, suffix: "pt")
                geometrySlider("Height", value: $preferences.cameraHeight, range: 22...64, suffix: "pt")
                geometrySlider("Horizontal offset", value: $preferences.horizontalOffset, range: -240...240, suffix: "pt")
                Button("Restore automatic geometry", systemImage: "arrow.counterclockwise") { preferences.resetGeometry() }
            }
        }.formStyle(.grouped)
    }
    private var integrations: some View {
        Form {
            Section("macOS HUD replacement") {
                HardwareKeysSettings(preferences: preferences, mediaKeys: model.mediaKeys)
            }
            Section("Now Playing") {
                Label("Music, Spotify and browser audio", systemImage: "music.note.list").font(.headline)
                Text("Open a player and start a track. Allow Automation access when macOS asks so the notch can read the artwork and control playback.").font(.caption).foregroundStyle(.secondary)
                Text("Browser audio appears automatically with its app icon and live audio levels. Browser track titles, artwork and transport controls are not provided by this adapter.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Open Music") { openPlayer("com.apple.Music") }
                    Button("Open Spotify") { openPlayer("com.spotify.client") }.disabled(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") == nil)
                    Spacer()
                    Button("Retry access") { media.retryPermissions() }
                }
                if !media.message.isEmpty { Text(media.message).font(.caption).foregroundStyle(.orange) }
                Button("Automation Settings…") { SystemActions.settings("privacy") }
            }
            Section("Live waveform") {
                Toggle("Analyze system audio", isOn: $preferences.waveformEnabled)
                Label(waveform.message, systemImage: waveform.active ? "waveform" : "info.circle").font(.caption).foregroundStyle(.secondary)
                Text("The bars show measured system audio only. With access off or unavailable, they stay still. Audio is never saved or uploaded.").font(.caption).foregroundStyle(.secondary)
            }
            Section("System controls") {
                Text("Wi-Fi, sound outputs, volume, battery notices, Bluetooth connections, USB notices, and Keep Awake use macOS services. Focus, Low Power Mode, and network pairing open System Settings.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private func geometrySlider(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack {
            Text(name).frame(width: 120, alignment: .leading)
            Slider(value: value, in: range, step: 1).disabled(!preferences.manualGeometry)
            Text("\(Int(value.wrappedValue)) \(suffix)").monospacedDigit().foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
        }
    }
    private func openPlayer(_ id: String) { if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { NSWorkspace.shared.open(url) } }
}

private struct HardwareKeysSettings: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var mediaKeys: MediaKeyService
    var body: some View {
        Toggle("Replace the macOS volume & brightness HUD", isOn: $preferences.replaceSystemHUD).disabled(!preferences.showOSD)
        Label(mediaKeys.message, systemImage: mediaKeys.status == .active ? "checkmark.circle.fill" : "keyboard")
            .font(.caption).foregroundStyle(.secondary)
        if preferences.replaceSystemHUD && mediaKeys.status != .active {
            Button("Enable Accessibility…") { mediaKeys.requestAccess() }
        }
        Text("Accessibility lets the notch handle volume and brightness keys before macOS displays its HUD. Option–Shift keeps fine adjustment; Option shortcuts and other keys retain their normal behavior.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
