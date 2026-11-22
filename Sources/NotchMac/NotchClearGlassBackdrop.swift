// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Not Boring Notch, Copyright (C) 2026 Allen Yi and contributors.
// Original: https://github.com/AllenReder/not-boring-notch/blob/063dc151e0dbb589a89dd816b9bebf5514402686/NotBoringNotch/components/Notch/LiquidGlass/LiquidGlassBackdropView.swift
// Modified for Dynanotch on 2026-11-20: zero blur, existing notch geometry and motion.
//
//  NotchClearGlassView.swift
//  NotBoringNotch
//

import AppKit
import Foundation
import QuartzCore
import SwiftUI

private typealias SetDoubleFunc = @convention(c) (AnyObject, Selector, Double) -> Void
private typealias SetObjFunc = @convention(c) (AnyObject, Selector, AnyObject) -> Void

final class NotchClearGlassView: NSView {
    static var isSupported: Bool {
        guard #available(macOS 26.0, *) else { return false }
        return ["CABackdropLayer", "CASDFLayer", "CASDFElementLayer", "CASDFOutputEffect", "CAFilter"]
            .allSatisfy { NSClassFromString($0) != nil }
    }

    /// The values the filter is built from. The representable supplies them
    /// from `LiquidGlassConfiguration`, so the view carries no defaults of its
    /// own that could drift from the shipped ones.
    var refraction: Double
    var lensHeight: Double
    var blur: Double
    var dispersion: Double
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    private var backdrop: CALayer?
    private var sdfLayer: CALayer?
    private var sdfElement: CALayer?

    init(
        frame: NSRect,
        refraction: Double,
        lensHeight: Double,
        blur: Double,
        dispersion: Double,
        topRadius: CGFloat,
        bottomRadius: CGFloat
    ) {
        self.refraction = refraction
        self.lensHeight = lensHeight
        self.blur = blur
        self.dispersion = dispersion
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
        super.init(frame: frame)
        wantsLayer = true
        setup()
        rebuild()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateGeometry()
    }

    private func setup() {
        guard let root = layer else { return }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let sdfLayerClass = NSClassFromString("CASDFLayer") as? CALayer.Type,
              let sdfElementClass = NSClassFromString("CASDFElementLayer") as? CALayer.Type,
              let sdfEffectClass = NSClassFromString("CASDFOutputEffect") as? NSObject.Type else {
            return
        }

        let backdropInstance = backdropClass.init()
        backdropInstance.frame = bounds
        backdropInstance.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backdropInstance.setValue(true, forKey: "tracksLuma")
        backdropInstance.setValue(true, forKey: "allowsFilteredLuma")
        backdropInstance.setValue(true, forKey: "windowServerAware")
        backdropInstance.allowsGroupOpacity = false

        // 1. CASDFOutputEffect converts distance field to normals
        let effect = sdfEffectClass.init()
        let selMin = NSSelectorFromString("setMinimum:")
        let selMax = NSSelectorFromString("setMaximum:")
        if let methodMin = class_getInstanceMethod(sdfEffectClass, selMin),
           let methodMax = class_getInstanceMethod(sdfEffectClass, selMax) {
            let impMin = unsafeBitCast(method_getImplementation(methodMin), to: SetDoubleFunc.self)
            let impMax = unsafeBitCast(method_getImplementation(methodMax), to: SetDoubleFunc.self)
            impMin(effect, selMin, -1000.0)
            impMax(effect, selMax, 1.0)
        }

        let sdfLayerInstance = sdfLayerClass.init()
        sdfLayerInstance.name = "@0"
        sdfLayerInstance.frame = bounds
        sdfLayerInstance.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        let selEffect = NSSelectorFromString("setEffect:")
        if let methodEffect = class_getInstanceMethod(sdfLayerClass, selEffect) {
            let imp = unsafeBitCast(method_getImplementation(methodEffect), to: SetObjFunc.self)
            imp(sdfLayerInstance, selEffect, effect)
        }

        // C1 Hermite Smoothness: eliminates hard step boundaries and color blocks
        let selSmooth = NSSelectorFromString("setSmoothness:")
        if let methodSmooth = class_getInstanceMethod(sdfLayerClass, selSmooth) {
            let imp = unsafeBitCast(method_getImplementation(methodSmooth), to: SetDoubleFunc.self)
            imp(sdfLayerInstance, selSmooth, 38.0)
        }

        // Inset the optical shape by the top radius to follow the notch walls.
        let sdfElementInstance = sdfElementClass.init()
        let contentWidth = max(bounds.width - topRadius * 2, 0)
        sdfElementInstance.frame = CGRect(x: topRadius, y: 0, width: contentWidth, height: bounds.height)
        sdfElementInstance.cornerRadius = bottomRadius
        sdfElementInstance.setValue("bounds", forKey: "mode")
        sdfElementInstance.setValue("union", forKey: "operation")

        sdfLayerInstance.sublayers = [sdfElementInstance]
        backdropInstance.sublayers = [sdfLayerInstance]
        root.addSublayer(backdropInstance)

        self.backdrop = backdropInstance
        self.sdfLayer = sdfLayerInstance
        self.sdfElement = sdfElementInstance
    }

    func updateGeometry() {
        guard let backdrop = backdrop,
              let sdfLayer = sdfLayer,
              let sdfElement = sdfElement else { return }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let contentFrame = CGRect(x: topRadius, y: 0, width: max(bounds.width - topRadius * 2, 0), height: bounds.height)
        guard backdrop.contentsScale != scale || backdrop.frame != bounds || sdfLayer.frame != bounds || sdfElement.frame != contentFrame
                || sdfElement.cornerRadius != bottomRadius else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.contentsScale = scale
        sdfLayer.contentsScale = scale
        sdfElement.contentsScale = scale
        backdrop.frame = bounds
        sdfLayer.frame = bounds
        sdfElement.frame = contentFrame
        sdfElement.cornerRadius = bottomRadius
        backdrop.setNeedsDisplay()
        sdfLayer.setNeedsDisplay()
        CATransaction.commit()
    }

    func rebuild() {
        guard let filterClass = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol,
              let backdrop = backdrop else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        guard let filter = filterClass.perform(NSSelectorFromString("filterWithType:"), with: "glassBackground")?.takeUnretainedValue() as AnyObject? else {
            CATransaction.commit()
            return
        }

        filter.setValue("glassBackground", forKey: "name")
        filter.setValue("@0", forKey: "inputSourceSublayerName")

        for (key, value) in Self.glassFilterInputs(
            refraction: refraction,
            lensHeight: lensHeight,
            blur: blur,
            dispersion: dispersion
        ) {
            filter.setValue(value, forKey: key)
        }

        backdrop.filters = [filter]
        backdrop.setNeedsDisplay()

        CATransaction.commit()
    }

    /// The numeric inputs for the private `glassBackground` filter, keyed by
    /// their CoreAnimation names. Held as data so the pipeline's rules can be
    /// read and checked without the private classes or a window server.
    static func glassFilterInputs(
        refraction: Double,
        lensHeight: Double,
        blur: Double,
        dispersion: Double
    ) -> [String: Double] {
        [
            // Optical ray bending around the SDF shape. Continuous across the
            // left, right and bottom walls, so no direction control is set.
            "inputInnerRefractionAmount": refraction,
            "inputInnerRefractionHeight": lensHeight,
            "inputRefractionDistance0": -1.0,
            "inputRefractionDistance1": 0.0,
            "inputRefractionOpacity": 1.0,

            // `Blur` drives the frost only. The blur-fill pass is a second,
            // wider blur composited outside the SDF refraction: any non-zero
            // fill opacity draws a translucent, unrefracted copy of the notch
            // beneath the refracted surface, so the whole pass stays off.
            "inputBlurRadius": blur,
            "inputBlurOpacity0": 0.85,
            "inputBlurOpacity1": 0.85,
            "inputBlurOpacity2": 1.0,
            "inputBlurOpacity3": 1.0,
            "inputBlurFillBlurRadius": 0.0,
            "inputBlurFillNormalOpacity": 0.0,
            "inputBlurFillLightenOpacity": 0.0,
            "inputBlurFillDarkenOpacity": 0.0,

            // The colour fringe hugs the same perimeter as the refraction, so
            // both passes share the lens height.
            "inputAberrationAmount": dispersion,
            "inputAberrationHeight": lensHeight,
            "inputAberrationOffset": 0.0,
            "inputAberrationAngle": 0.0,

            // Crystal clear: an opaque face with nothing bleeding past it.
            "inputBleedAmount": 0.0,
            "inputFaceOpacity": 1.0,
            "inputShadowAmount": 0.0,
            "inputKeyFillHighlightAmount": 0.50,
        ]
    }
}

// MARK: - SwiftUI Representable

struct NotchClearGlassBackdrop: NSViewRepresentable {
    var refraction: Double = 32
    var lensHeight: Double = 44
    var blur: Double = 0
    var dispersion: Double = 0.35
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    func makeNSView(context: Context) -> NotchClearGlassView {
        NotchClearGlassView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 195),
            refraction: -refraction,
            lensHeight: lensHeight,
            blur: blur,
            dispersion: dispersion,
            topRadius: topRadius,
            bottomRadius: bottomRadius
        )
    }

    func updateNSView(_ nsView: NotchClearGlassView, context: Context) {
        let changed = nsView.refraction != -refraction || nsView.lensHeight != lensHeight
            || nsView.blur != blur || nsView.dispersion != dispersion
        nsView.refraction = -refraction
        nsView.lensHeight = lensHeight
        nsView.blur = blur
        nsView.dispersion = dispersion
        nsView.topRadius = topRadius
        nsView.bottomRadius = bottomRadius
        nsView.updateGeometry()
        if changed { nsView.rebuild() }
    }
}

