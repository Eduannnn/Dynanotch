import Foundation
import CoreGraphics

/// Passive visual response, independent of the window's interactive hit region.
public struct EdgeLighting: Equatable, Sendable {
    public var point: CGPoint
    public var strength: Double
    public init(point: CGPoint = CGPoint(x: 0.25, y: 0.1), strength: Double = 0) {
        self.point = point; self.strength = strength
    }
    public static func response(to pointer: CGPoint, around frame: CGRect, reach: CGFloat = 100) -> EdgeLighting {
        guard frame.width > 0, frame.height > 0, reach > 0 else { return .init() }
        let dx = max(frame.minX - pointer.x, 0, pointer.x - frame.maxX)
        let dy = max(frame.minY - pointer.y, 0, pointer.y - frame.maxY)
        let strength = max(0, 1 - hypot(dx, dy) / reach)
        guard strength > 0 else { return .init() }
        return .init(point: CGPoint(x: min(1, max(0, (pointer.x - frame.minX) / frame.width)),
                                    y: min(1, max(0, (frame.maxY - pointer.y) / frame.height))),
                     strength: Double(strength))
    }
}
