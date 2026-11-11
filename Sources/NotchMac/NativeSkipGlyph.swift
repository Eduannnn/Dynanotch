import AppKit
import SwiftUI
import QuartzCore
import ObjectiveC

@objc private protocol NativeSkipStateController: NSObjectProtocol {
    @objc(initWithLayer:) init(layer: CALayer)
    @objc(setInitialStatesOfLayer:) func setInitialStates(of layer: CALayer)
    @objc(setState:ofLayer:transitionSpeed:) func setState(_ state: NSObject?, of layer: CALayer, transitionSpeed: Float)
}

/// Reads the installed Apple animation in our process. No resource is copied or modified.
@MainActor private final class NativeSkipPackage {
    static let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/NowPlayingUI.framework/Resources/ForwardBackward.caar")
    let root: CALayer
    let inkBounds: CGRect
    private let package: NSObject
    private let controller: NativeSkipStateController
    private let states: [NSObject]
    private var index = 0
    private(set) var lastVisibleArrowTravel: CGFloat = 0
    var stateName: String { "State \(index + 1)" }
    var activeAnimationCount: Int {
        func count(_ layer: CALayer) -> Int {
            (layer.animationKeys()?.count ?? 0) + (layer.sublayers ?? []).reduce(0) { $0 + count($1) }
        }
        return count(root)
    }
    private var visibleArrowPositions: [String: CGFloat] {
        var positions: [String: CGFloat] = [:]
        func visit(_ layer: CALayer) {
            if let name = layer.name, name.hasPrefix("ffwd"), name.hasSuffix(" shape"),
               !layer.isHidden, layer.opacity > 0.01, abs(layer.transform.m11) > 0.01 {
                positions[name] = layer.position.x
            }
            layer.sublayers?.forEach(visit)
        }
        visit(root); return positions
    }

    init?() {
        let loadSelector = NSSelectorFromString("packageWithContentsOfURL:type:options:error:")
        guard FileManager.default.isReadableFile(atPath: Self.url.path),
              let packageClass = NSClassFromString("CAPackage"),
              let loadMethod = class_getClassMethod(packageClass, loadSelector),
              method_getNumberOfArguments(loadMethod) == 6,
              let controllerClass = NSClassFromString("CAStateController"),
              class_getInstanceMethod(controllerClass, NSSelectorFromString("initWithLayer:")) != nil,
              class_getInstanceMethod(controllerClass, NSSelectorFromString("setInitialStatesOfLayer:")) != nil,
              class_getInstanceMethod(controllerClass, NSSelectorFromString("setState:ofLayer:transitionSpeed:")) != nil else { return nil }
        typealias Loader = @convention(c) (AnyObject, Selector, NSURL, NSString, NSDictionary?, UnsafeMutableRawPointer?) -> Unmanaged<AnyObject>?
        let load = unsafeBitCast(method_getImplementation(loadMethod), to: Loader.self)
        guard let package = load(packageClass as AnyObject, loadSelector, Self.url as NSURL,
                                 "com.apple.coreanimation-archive", nil, nil)?.takeUnretainedValue() as? NSObject,
              package.responds(to: NSSelectorFromString("rootLayer")),
              let root = package.perform(NSSelectorFromString("rootLayer"))?.takeUnretainedValue() as? CALayer,
              root.responds(to: NSSelectorFromString("states")),
              let states = root.perform(NSSelectorFromString("states"))?.takeUnretainedValue() as? [NSObject],
              states.count == 4,
              states.enumerated().allSatisfy({ $0.element.responds(to: NSSelectorFromString("name"))
                  && $0.element.value(forKey: "name") as? String == "State \($0.offset + 1)" }) else { return nil }
        self.package = package; self.root = root; self.states = states
        let controllerType = unsafeBitCast(controllerClass, to: NativeSkipStateController.Type.self)
        controller = controllerType.init(layer: root)
        controller.setInitialStates(of: root)
        // State 1 is the resting pose, not a skip. Prime it before receiving taps.
        controller.setState(states[0], of: root, transitionSpeed: 0)
        var ink = CGRect.null
        func visit(_ layer: CALayer, opacity: Float) {
            let visible = opacity * layer.opacity
            guard !layer.isHidden, visible > 0.01 else { return }
            if let shape = layer as? CAShapeLayer, layer.name?.hasSuffix("-tint-shape") == true, let path = shape.path {
                shape.fillColor = NSColor.white.withAlphaComponent(0.88).cgColor
                ink = ink.union(shape.convert(path.boundingBoxOfPath, to: root))
            }
            layer.sublayers?.forEach { visit($0, opacity: visible) }
        }
        visit(root, opacity: 1)
        // Also tint the initially invisible arrows that enter on subsequent taps.
        func tint(_ layer: CALayer) {
            layer.removeAllAnimations()
            if let shape = layer as? CAShapeLayer, layer.name?.hasSuffix("-tint-shape") == true {
                shape.fillColor = NSColor.white.withAlphaComponent(0.88).cgColor
            }
            layer.sublayers?.forEach(tint)
        }
        tint(root)
        guard !ink.isNull, ink.width > 0, ink.height > 0 else { return nil }
        inkBounds = ink
    }
    func advance() {
        let before = visibleArrowPositions
        index = (index + 1) % states.count
        controller.setState(states[index], of: root, transitionSpeed: 1)
        lastVisibleArrowTravel = visibleArrowPositions.compactMap { name, x in before[name].map { abs(x - $0) } }.max() ?? 0
    }
}

@MainActor final class NativeSkipGlyphHost: NSView {
    private let animation = NativeSkipPackage()
    private let fallback = NSImageView()
    private var lastTrigger: Int?
    private var backwards = false
    var loadedNativeAnimation: Bool { animation != nil }
    var stateName: String { animation?.stateName ?? "fallback" }
    var activeNativeAnimationCount: Int { animation?.activeAnimationCount ?? 0 }
    var lastVisibleArrowTravel: CGFloat { animation?.lastVisibleArrowTravel ?? 0 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.backgroundColor = NSColor.clear.cgColor
        if let animation { layer?.addSublayer(animation.root) }
        else {
            fallback.imageScaling = .scaleProportionallyUpOrDown
            fallback.contentTintColor = .white.withAlphaComponent(0.88)
            addSubview(fallback)
        }
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(backwards: Bool, trigger: Int, reduceMotion: Bool) {
        self.backwards = backwards
        if animation == nil {
            fallback.image = NSImage(systemSymbolName: backwards ? "backward.fill" : "forward.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 24, weight: .semibold))
        }
        if let lastTrigger, trigger != lastTrigger {
            if !reduceMotion { animation?.advance() }
        }
        // A newly mounted representable adopts the current trigger without replaying it.
        lastTrigger = trigger
        needsLayout = true
    }
    override func layout() {
        super.layout()
        fallback.frame = bounds
        guard let animation, bounds.width > 0, bounds.height > 0 else { return }
        let ink = animation.inkBounds
        let scale = min(bounds.width / ink.width, bounds.height / ink.height)
        let xScale = backwards ? -scale : scale
        CATransaction.begin(); CATransaction.setDisableActions(true)
        animation.root.anchorPoint = .zero
        animation.root.setAffineTransform(.init(scaleX: xScale, y: scale))
        animation.root.position = CGPoint(x: bounds.midX - ink.midX * xScale, y: bounds.midY - ink.midY * scale)
        CATransaction.commit()
    }
}

struct NativeSkipGlyph: NSViewRepresentable {
    var backwards: Bool
    var trigger: Int
    var reduceMotion: Bool
    func makeNSView(context: Context) -> NativeSkipGlyphHost { NativeSkipGlyphHost(frame: .zero) }
    func updateNSView(_ view: NativeSkipGlyphHost, context: Context) {
        view.update(backwards: backwards, trigger: trigger, reduceMotion: reduceMotion)
    }
}
