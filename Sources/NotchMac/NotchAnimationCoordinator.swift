import AppKit
import QuartzCore
import Combine
import NotchCore

struct NotchSurface: Equatable {
    var width: CGFloat
    var height: CGFloat
    var offset: CGFloat
    var radius: CGFloat
    var ear: CGFloat
    var artworkX: CGFloat = 19
    var artworkY: CGFloat = 18
    var artworkSize: CGFloat = 28
}

/// One frame clock owns all five chrome properties. No implicit geometry animations compete.
@MainActor final class NotchAnimationCoordinator: NSObject, ObservableObject {
    @Published private(set) var surface = NotchSurface(width: 208, height: 37.5, offset: 0, radius: 12, ear: 6)
    private var values: [MotionValue] = []
    private var link: CADisplayLink?
    private var lastTime = CACurrentMediaTime()
    private var target = NotchSurface(width: 208, height: 37.5, offset: 0, radius: 12, ear: 6)
    var onFrame: ((NotchSurface) -> Void)?
    private(set) var frameCount = 0
    var isAnimating: Bool { link != nil }

    func update(_ next: NotchSurface, screen: NSScreen?, immediate: Bool = false) {
        let components = [next.width, next.height, next.offset, next.radius, next.ear,
                          next.artworkX, next.artworkY, next.artworkSize].map(Double.init)
        let now = CACurrentMediaTime()
        if values.isEmpty {
            values = components.map(MotionValue.init)
            target = next; surface = next; onFrame?(next); return
        }
        if link != nil { advance(to: now) }
        target = next
        for i in values.indices { values[i].target = components[i] }
        if immediate || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            for i in values.indices { values[i].settle() }
            stop(); surface = next; onFrame?(next); return
        }
        if values.allSatisfy(\.settled) { publish(); return }
        if link == nil, let screen = screen ?? NSScreen.main {
            lastTime = now
            link = screen.displayLink(target: self, selector: #selector(tick(_:)))
            link?.add(to: .main, forMode: .common)
        }
    }
    @objc private func tick(_ sender: CADisplayLink) {
        frameCount += 1
        advance(to: CACurrentMediaTime())
        if values.allSatisfy(\.settled) {
            for i in values.indices { values[i].settle() }
            stop()
        }
        publish()
    }
    private func advance(to now: Double) {
        let dt = max(0, now-lastTime); lastTime = now
        for i in values.indices { values[i].advance(seconds: dt) }
    }
    private func publish() {
        guard values.count == 8 else { return }
        surface = .init(width: max(1, values[0].value), height: max(1, values[1].value),
                        offset: values[2].value, radius: max(0, values[3].value), ear: max(0, values[4].value),
                        artworkX: values[5].value, artworkY: values[6].value, artworkSize: max(1, values[7].value))
        onFrame?(surface)
    }
    func stop() { link?.invalidate(); link = nil }
}
