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
    var waveformInset: CGFloat = 19
    var waveformY: CGFloat = 18
}

/// One frame clock moves the silhouette, artwork and waveform together.
@MainActor final class NotchAnimationCoordinator: NSObject, ObservableObject {
    @Published private(set) var surface = NotchSurface(width: 208, height: 37.5, offset: 0, radius: 12, ear: 6)
    private var values: [MotionValue] = []
    private var link: AnyObject?
    private var usesRunLoopTimer = false
    private var invalidateLink: (() -> Void)?
    private var lastTime = CACurrentMediaTime()
    private var target = NotchSurface(width: 208, height: 37.5, offset: 0, radius: 12, ear: 6)
    var response = 0.32
    var damping = 0.88
    var onFrame: ((NotchSurface) -> Void)?
    private(set) var frameCount = 0
    var isAnimating: Bool { link != nil }

    func update(_ next: NotchSurface, screen: NSScreen?, immediate: Bool = false, useRunLoopTimer: Bool = false) {
        let components = [next.width, next.height, next.offset, next.radius, next.ear,
                          next.artworkX, next.artworkY, next.artworkSize,
                          next.waveformInset, next.waveformY].map(Double.init)
        let now = CACurrentMediaTime()
        if values.isEmpty {
            values = components.map(MotionValue.init)
            target = next; surface = next; onFrame?(next); return
        }
        if link != nil {
            advance(to: now)
            if useRunLoopTimer != usesRunLoopTimer { stop() }
        }
        target = next
        for i in values.indices { values[i].target = components[i] }
        if immediate || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            for i in values.indices { values[i].settle() }
            stop(); surface = next; onFrame?(next); return
        }
        if values.allSatisfy(\.settled) { publish(); return }
        if link == nil {
            lastTime = now
            usesRunLoopTimer = useRunLoopTimer
            if !useRunLoopTimer, #available(macOS 14.0, *), let screen = screen ?? NSScreen.main {
                let displayLink = screen.displayLink(target: self, selector: #selector(tick(_:)))
                link = displayLink; invalidateLink = { displayLink.invalidate() }
                displayLink.add(to: .main, forMode: .common)
            } else {
                let timer = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] timer in self?.tick(timer) }
                link = timer; invalidateLink = { timer.invalidate() }
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }
    @objc private func tick(_ sender: AnyObject) {
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
        for i in values.indices { values[i].advance(seconds: dt, response: max(0.05, response), damping: damping) }
    }
    private func publish() {
        guard values.count == 10 else { return }
        surface = .init(width: max(1, values[0].value), height: max(1, values[1].value),
                        offset: values[2].value, radius: max(0, values[3].value), ear: max(0, values[4].value),
                        artworkX: values[5].value, artworkY: values[6].value, artworkSize: max(1, values[7].value),
                        waveformInset: values[8].value, waveformY: values[9].value)
        onFrame?(surface)
    }
    func stop() { invalidateLink?(); invalidateLink = nil; link = nil }
}
