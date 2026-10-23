import Foundation

/// Computes where every managed window should be. Pure.
public struct Planner: Sendable {
    public struct Target: Equatable, Sendable {
        public let id: WindowID
        public let frame: Rect
        public let visible: Bool
    }

    public let displays: [Display]
    public let gap: Double

    public init(displays: [Display], gap: Double) {
        self.displays = displays; self.gap = gap
    }

    /// Visible windows first, so that the target project appears before the old one disappears.
    public func plan(
        records: [WindowID: WindowRecord],
        facts: [WindowID: WindowFacts],
        isVisible: (WindowRecord) -> Bool,
        displayOf: (String) -> Display
    ) -> [Target] {
        var shown: [Target] = []
        var hidden: [Target] = []
        for (id, record) in records.sorted(by: { $0.key < $1.key }) {
            guard let f = facts[id], !f.isFrozen else { continue }
            let display = displayOf(record.workspace)
            if isVisible(record) {
                shown.append(Target(id: id, frame: onScreenFrame(record, current: f.frame, on: display), visible: true))
            } else {
                hidden.append(Target(id: id, frame: parkedFrame(size: f.frame, on: display), visible: false))
            }
        }
        return shown + hidden
    }

    public func onScreenFrame(_ record: WindowRecord, current: Rect, on display: Display) -> Rect {
        let area = display.visibleFrame
        guard record.floating else { return area.insetBy(gap) }
        var r = record.floatingFrame ?? current
        let c = r.center
        if !area.contains(x: c.x, y: c.y) {
            // The workspace moved to another display, or the window was parked: center it.
            r.width = min(r.width, area.width)
            r.height = min(r.height, area.height)
            r.x = area.x + (area.width - r.width) / 2
            r.y = area.y + (area.height - r.height) / 2
        }
        return r
    }

    /// Off-screen in a bottom corner with 1pt left visible, as AeroSpace does. macOS keeps windows
    /// partially on screen, so the corner must not touch a neighbouring display.
    public func parkedFrame(size: Rect, on display: Display) -> Rect {
        let f = display.frame
        let hasRightNeighbour = displays.contains { $0.id != display.id && $0.frame.x >= f.maxX - 1 }
        let x = hasRightNeighbour ? f.x - size.width + 1 : f.maxX - 1
        return Rect(x: x, y: f.maxY - 1, width: size.width, height: size.height)
    }

    /// True if the frame looks like a real on-screen position (not parked).
    public func isOnScreen(_ r: Rect) -> Bool {
        let c = r.center
        return displays.contains { $0.frame.contains(x: c.x, y: c.y) }
    }
}
