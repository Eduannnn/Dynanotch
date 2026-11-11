import Foundation

/// Two identical text copies move left, pausing at the start and end of a title.
/// At the wrap, copy two occupies exactly the previous position of copy one.
public struct RibbonFrame {
    public let offset: Double
    public let fadedEdges: Bool
    public static func at(elapsed: Double, textWidth: Double, viewportWidth: Double) -> Self {
        guard elapsed.isFinite, textWidth.isFinite, viewportWidth.isFinite,
              viewportWidth > 0, textWidth - viewportWidth > 2 else { return .init(offset: 0, fadedEdges: false) }
        let speed = 30.0, pause = 1.5, lead = 0.2
        let overflow = textWidth - viewportWidth
        let cycleWidth = textWidth + 36
        let firstTravel = overflow / speed
        let wrapTravel = (cycleWidth - overflow) / speed
        let cycle = pause * 2 + firstTravel + wrapTravel
        let t = max(0, elapsed).truncatingRemainder(dividingBy: cycle)
        let wrapStart = pause * 2 + firstTravel
        let offset: Double
        if t < pause { offset = 0 }
        else if t < pause + firstTravel { offset = -(t - pause) * speed }
        else if t < wrapStart { offset = -overflow }
        else { offset = -overflow - (t - wrapStart) * speed }
        let fade = (t >= pause - lead && t < max(pause, pause + firstTravel - lead))
            || (t >= wrapStart - lead && t < cycle - lead)
        return .init(offset: offset, fadedEdges: fade)
    }
}
