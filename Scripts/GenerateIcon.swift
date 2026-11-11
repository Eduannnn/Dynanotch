import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let sizes = [16, 32, 128, 256, 512]
for size in sizes {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let base = NSBezierPath(roundedRect: NSRect(x: 22, y: 22, width: 980, height: 980), xRadius: 224, yRadius: 224)
        NSGradient(starting: NSColor(red: 0.13, green: 0.19, blue: 0.24, alpha: 1), ending: NSColor(red: 0.02, green: 0.03, blue: 0.04, alpha: 1))!.draw(in: base, angle: -55)
        let device = NSBezierPath(roundedRect: NSRect(x: 159, y: 246, width: 706, height: 534), xRadius: 63, yRadius: 63)
        NSColor(white: 0.30, alpha: 1).setStroke(); device.lineWidth = 13; device.stroke()
        NSColor.black.setFill(); device.fill()
        NSColor(red: 0.18, green: 0.27, blue: 0.33, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 179, y: 266, width: 666, height: 494), xRadius: 45, yRadius: 45).fill()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 362, y: 679, width: 300, height: 119), xRadius: 29, yRadius: 29).fill()
        let config = NSImage.SymbolConfiguration(pointSize: 235, weight: .medium)
        if let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let tinted = NSImage(size: symbol.size)
            tinted.lockFocus(); symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor(red: 0.29, green: 1, blue: 0.99, alpha: 1).setFill(); NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop); tinted.unlockFocus()
            tinted.draw(in: NSRect(x: 325, y: 355, width: 374, height: 260))
        }
        NSColor(white: 0.25, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 120, y: 213, width: 784, height: 25), xRadius: 12, yRadius: 12).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
