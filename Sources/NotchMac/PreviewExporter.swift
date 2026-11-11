import SwiftUI
import AppKit
import NotchCore

@MainActor enum PreviewExporter {
    static func export(model: NotchModel, directory: String) {
        let destination = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        model.setPreview(true)
        model.system.loadRenderingPreview()
        model.cameraWidth = 180; model.cameraHeight = 32
        let idle = NotchModel()
        idle.system.loadRenderingPreview(); idle.cameraWidth = 180; idle.cameraHeight = 32
        save(model: idle, title: "BATTERY & WI-FI", name: "Idle.png", width: 560, height: 155, destination: destination)
        model.peek = false; model.hovering = true
        save(model: model, title: "NOW PLAYING", name: "Player.png", width: 560, height: 330, destination: destination)
        model.hovering = false; model.peek = false
        save(model: model, title: "COLLAPSED · MEDIA", name: "Collapsed.png", width: 560, height: 155, destination: destination)
        model.previewNotice()
        save(model: model, title: "COLLAPSED · BLUETOOTH", name: "DeviceNotice.png", width: 560, height: 155, destination: destination)
        let maxNotice = NotchModel()
        maxNotice.system.loadRenderingPreview(); maxNotice.cameraWidth = 180; maxNotice.cameraHeight = 32
        maxNotice.enqueue(.init(key: "preview/airpods-max", name: "AirPods Max", kind: .headphones, battery: 0.75, airPodsArtwork: .init(family: .airpodsMax)))
        save(model: maxNotice, title: "COLLAPSED · AIRPODS MAX", name: "AirPodsMaxNotice.png", width: 560, height: 155, destination: destination)
        model.showOSD(.init(kind: .volume, level: 0.64, muted: false))
        save(model: model, title: "COLLAPSED · VOLUME", name: "Volume.png", width: 560, height: 155, destination: destination)
        model.showOSD(.init(kind: .brightness, level: 0.8, muted: false))
        save(model: model, title: "COLLAPSED · BRIGHTNESS", name: "Brightness.png", width: 560, height: 155, destination: destination)
        let charging = NotchModel()
        charging.system.loadRenderingPreview(battery: 0.72, charging: true); charging.cameraWidth = 180; charging.cameraHeight = 32
        charging.previewCharging()
        save(model: charging, title: "COLLAPSED · CHARGING", name: "Charging.png", width: 560, height: 155, destination: destination)
        let critical = NotchModel()
        critical.system.loadRenderingPreview(battery: 0.05); critical.cameraWidth = 180; critical.cameraHeight = 32
        save(model: critical, title: "BATTERY · 5 PERCENT", name: "CriticalBattery.png", width: 560, height: 155, destination: destination)
        critical.system.loadRenderingPreview(battery: 0.05, charging: true)
        save(model: critical, title: "CHARGING · 5 PERCENT", name: "ChargingCriticalBattery.png", width: 560, height: 155, destination: destination)
        let usb = NotchModel()
        usb.system.loadRenderingPreview(); usb.cameraWidth = 180; usb.cameraHeight = 32
        usb.enqueue(.init(key: "preview/usb", name: "USB Headset", kind: .headphones, transport: "USB"))
        save(model: usb, title: "COLLAPSED · USB", name: "USBNotice.png", width: 560, height: 155, destination: destination)
    }
    private static func save(model: NotchModel, title: String, name: String, width: CGFloat, height: CGFloat, destination: URL) {
        let content = VStack(spacing: 0) {
            HStack {
                Label("Dynanotch", systemImage: "macbook.gen2").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("SWIFTUI PREVIEW").font(.system(size: 8, weight: .medium)).tracking(1.5).foregroundStyle(.white.opacity(0.4))
            }.foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 26).frame(height: 50)
            NotchRootView(model: model).environment(\.staticNotchPreview, true)
                .frame(width: width, height: height - 94, alignment: .top).clipped()
            Spacer(minLength: 0)
            Text(title).font(.system(size: 9, weight: .medium)).tracking(2.5).foregroundStyle(.white.opacity(0.4)).frame(height: 32)
        }.frame(width: width, height: height).background(LinearGradient(colors: [Color(red: 0.13, green: 0.17, blue: 0.21), Color(red: 0.065, green: 0.08, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: destination.appendingPathComponent(name))
    }
}
