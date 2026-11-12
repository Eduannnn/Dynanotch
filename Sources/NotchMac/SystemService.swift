import AppKit
import Combine
import CoreWLAN
import IOBluetooth
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import Network
import NotchCore

struct BluetoothItem: Identifiable, Equatable {
    var id: String
    var name: String
    var connected: Bool
    var kind: NoticeKind
    var airPodsArtwork: AirPodsArtwork? = nil
    var airPodsBattery: AirPodsBatteryDetails? = nil
}

struct SystemSnapshot: Equatable {
    var battery: Double?
    var onAC = false
    var charging = false
    var lowPower = false
    var wifiOn = false
    var wifiName = "Not connected"
    var networkConnected = false
    var bluetoothOn = false
    var devices: [BluetoothItem] = []
}

@MainActor final class SystemService: ObservableObject {
    @Published private(set) var state = SystemSnapshot()
    @Published private(set) var keepAwake = false
    @Published var message = ""
    var onNotice: ((DeviceNotice) -> Void)?
    var onDeviceBatteryUpdated: ((String, Double?) -> Void)?
    var onArtworkUpdated: ((String, AirPodsArtwork) -> Void)?
    var onBatteryUpdated: ((Double?) -> Void)?
    var onUnplugged: (() -> Void)?
    private var timer: Timer?
    private var busy = false
    private var powerBusy = false
    private var powerInitialized = false
    private let powerQueue = DispatchQueue(label: "com.eduannnn.notch.power", qos: .utility)
    private var initialized = false
    private var warningStage = 0
    private var knownUSB: [String: String] = [:]
    private var assertion: IOPMAssertionID = 0
    private let queue = DispatchQueue(label: "com.eduannnn.notch.system", qos: .utility)
    private let network = NWPathMonitor()
    private var networkConnected = false

    func start() {
        network.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.networkConnected = path.status == .satisfied }
        }
        network.start(queue: powerQueue)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        timer?.tolerance = 0.4
    }

    private func refresh() {
        refreshPower()
        guard !busy else { return }
        busy = true
        queue.async { [weak self] in
            var result = SystemSnapshot()
            result.bluetoothOn = IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
            let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
            let discovered = devices.map { device in
                let name = device.name ?? "Bluetooth device"
                let artwork = BluetoothArtworkMetadata.artwork(for: device)
                let kind: NoticeKind = artwork.map { $0.family == .airpodsMax ? .headphones : .earbuds } ?? .device(named: name)
                let connected = device.isConnected()
                let address = device.addressString.flatMap { $0.isEmpty ? nil : $0 }
                return BluetoothItem(id: address ?? "name/" + name, name: name, connected: connected, kind: kind,
                                     airPodsArtwork: artwork, airPodsBattery: connected && artwork != nil
                                         ? BluetoothArtworkMetadata.battery(for: device) : nil)
            }
            let unique = Dictionary(discovered.map { ($0.id, $0) }, uniquingKeysWith: { first, second in
                second.connected && !first.connected ? second : first
            })
            result.devices = unique.values.sorted { lhs, rhs in
                if lhs.connected != rhs.connected { return lhs.connected }
                return lhs.name != rhs.name ? lhs.name < rhs.name : lhs.id < rhs.id
            }
            let usb = Self.readUSB()
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                result.battery = self.state.battery; result.onAC = self.state.onAC
                result.charging = self.state.charging; result.lowPower = self.state.lowPower
                result.networkConnected = self.state.networkConnected; result.wifiOn = self.state.wifiOn; result.wifiName = self.state.wifiName
                self.accept(result, usb: usb)
            }
        }
    }

    // Power notices must keep updating even if a hardware lookup stalls.
    private func refreshPower() {
        guard !powerBusy else { return }
        powerBusy = true
        let connected = networkConnected
        powerQueue.async { [weak self] in
            var result = Self.readBattery()
            result.networkConnected = connected
            if let interface = CWWiFiClient.shared().interface() {
                result.wifiOn = interface.powerOn()
                result.wifiName = interface.ssid() ?? (interface.activePHYMode() != .modeNone ? "Connected" : "Not connected")
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.powerBusy = false
                self.acceptPower(result)
            }
        }
    }

    private func acceptPower(_ next: SystemSnapshot) {
        if powerInitialized {
            if !state.onAC && next.onAC, let battery = next.battery {
                onNotice?(.init(key: "power/system-battery", name: "Charging", kind: .charging, transport: "Power", battery: battery))
            }
            if state.onAC && !next.onAC { onUnplugged?() }
        }
        if let level = next.battery, !next.onAC {
            let stage = level <= 0.05 ? 2 : level <= 0.2 ? 1 : 0
            if stage > warningStage {
                onNotice?(.init(key: "power/warning/\(stage)", name: stage == 2 ? "Battery critical" : "Low battery", kind: stage == 2 ? .batteryCritical : .batteryLow, transport: "Power", battery: level))
            }
            warningStage = stage
        } else { warningStage = 0 }
        if next.battery != state.battery { onBatteryUpdated?(next.battery) }
        powerInitialized = true
        state.battery = next.battery; state.onAC = next.onAC
        state.charging = next.charging; state.lowPower = next.lowPower
        state.networkConnected = next.networkConnected; state.wifiOn = next.wifiOn; state.wifiName = next.wifiName
    }

    private func accept(_ next: SystemSnapshot, usb: [String: String]) {
        if initialized {
            let previous = Dictionary(state.devices.map { ($0.id, $0.connected) }, uniquingKeysWith: { $0 || $1 })
            for device in next.devices where device.connected != (previous[device.id] ?? false) {
                onNotice?(.init(key: device.id, name: device.name, kind: device.kind, connected: device.connected, battery: device.airPodsBattery?.listeningLevel, airPodsArtwork: device.airPodsArtwork))
            }
            for (id, name) in usb where knownUSB[id] == nil {
                onNotice?(.init(key: "usb/" + id, name: name, kind: .device(named: name, fallback: .usb), transport: "USB"))
            }
            for (id, name) in knownUSB where usb[id] == nil {
                onNotice?(.init(key: "usb/" + id, name: name, kind: .device(named: name, fallback: .usb), transport: "USB", connected: false))
            }
        }
        for device in next.devices where device.connected {
            if let artwork = device.airPodsArtwork { onArtworkUpdated?(device.id, artwork) }
            let previousBattery = state.devices.first(where: { $0.id == device.id })?.airPodsBattery?.listeningLevel
            if device.airPodsBattery?.listeningLevel != previousBattery {
                onDeviceBatteryUpdated?(device.id, device.airPodsBattery?.listeningLevel)
            }
        }
        knownUSB = usb; initialized = true
        if state != next { state = next }
    }

    nonisolated private static func readBattery() -> SystemSnapshot {
        var result = SystemSnapshot()
        result.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return result }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let capacity = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 0
            if maximum > 0 { result.battery = unit(capacity / maximum) }
            result.onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            result.charging = description[kIOPSIsChargingKey] as? Bool ?? false
            break
        }
        return result
    }

    nonisolated private static func readUSB() -> [String: String] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var result: [String: String] = [:]
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any] {
                let name = dictionary["USB Product Name"] as? String ?? dictionary["Product Name"] as? String ?? "USB device"
                let builtIn = (dictionary["Built-In"] as? NSNumber)?.boolValue ?? false
                if !builtIn && !name.localizedCaseInsensitiveContains("internal") {
                    var id: UInt64 = 0
                    if IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS { result[String(id)] = name }
                }
            }
            IOObjectRelease(service); service = IOIteratorNext(iterator)
        }
        return result
    }

    func toggleKeepAwake() {
        if keepAwake {
            if assertion != 0 { IOPMAssertionRelease(assertion) }; assertion = 0; keepAwake = false
        } else {
            let status = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Dynanotch Keep Awake" as CFString, &assertion)
            if status == kIOReturnSuccess { keepAwake = true } else { message = "Could not enable Keep Awake." }
        }
    }

    func setWiFiPower(_ enabled: Bool) {
        queue.async { [weak self] in
            do { try CWWiFiClient.shared().interface()?.setPower(enabled) }
            catch { DispatchQueue.main.async { self?.message = "Wi-Fi could not be changed. Open Wi-Fi Settings to continue." } }
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func toggleDevice(_ item: BluetoothItem) {
        queue.async { [weak self] in
            guard let device = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?.first(where: { $0.addressString == item.id }) else { return }
            let status = item.connected ? device.closeConnection() : device.openConnection()
            DispatchQueue.main.async {
                if status != kIOReturnSuccess { self?.message = "Could not change the connection to \(item.name). Try Bluetooth Settings." }
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate(); network.cancel()
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
    }

    func loadRenderingPreview(battery: Double = 0.72, charging: Bool = false,
                              devices: [BluetoothItem] = [.init(id: "preview", name: "AirPods Pro", connected: true, kind: .earbuds)]) {
        // Explicitly limited to the labeled, exported UI previews; never used by the running app.
        state = .init(battery: battery, onAC: charging, charging: charging, lowPower: false, wifiOn: true, wifiName: "Connected", networkConnected: true, bluetoothOn: true, devices: devices)
    }
}

@MainActor enum SystemActions {
    static func settings(_ pane: String) {
        let targets = [
            "wifi": "com.apple.wifi-settings-extension",
            "bluetooth": "com.apple.BluetoothSettings",
            "focus": "com.apple.Focus-Settings.extension",
            "battery": "com.apple.Battery-Settings.extension",
            "display": "com.apple.Displays-Settings.extension",
            "sound": "com.apple.Sound-Settings.extension",
            "privacy": "com.apple.preference.security?Privacy_Automation"
        ]
        guard let target = targets[pane], let url = URL(string: "x-apple.systempreferences:" + target) else { return }
        NSWorkspace.shared.open(url)
    }

    static func power(_ action: String) {
        guard ["sleep", "restart", "shut down"].contains(action) else { return }
        if action != "sleep" {
            let alert = NSAlert()
            alert.messageText = action == "restart" ? "Restart your Mac?" : "Shut down your Mac?"
            alert.informativeText = "Save your work before continuing."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: action == "restart" ? "Restart" : "Shut Down")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        AppleScriptExecutor.submit {
            let (_, error) = AppleScriptExecutor.execute("with timeout of 5 seconds\ntell application \"System Events\" to \(action)\nend timeout")
            if error != nil {
                DispatchQueue.main.async {
                    let alert = NSAlert(); alert.messageText = "macOS could not complete the power action."
                    alert.informativeText = "Use the Apple menu, or allow Dynanotch to control System Events in Privacy & Security → Automation."
                    alert.runModal()
                }
            }
        }
    }
}
