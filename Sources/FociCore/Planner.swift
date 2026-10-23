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
        displayOf: (String) -> Display,
        layoutOf: (String) -> Layout
    ) -> [Target] {
        var shown: [Target] = []
        var hidden: [Target] = []
        var tiled: [String: [(WindowID, WindowRecord)]] = [:]
        for (id, record) in records.sorted(by: { $0.key < $1.key }) {
            guard let f = facts[id], !f.isFrozen else { continue }
            let display = displayOf(record.workspace)
            if !isVisible(record) {
                hidden.append(Target(id: id, frame: parkedFrame(size: f.frame, on: display), visible: false))
            } else if record.floating {
                shown.append(Target(id: id, frame: floatingFrame(record, current: f.frame, on: display), visible: true))
            } else {
                tiled[record.workspace, default: []].append((id, record))
            }
        }
        for (ws, windows) in tiled.sorted(by: { $0.key < $1.key }) {
            let ordered = windows.sorted { ($0.1.seq, $0.0) < ($1.1.seq, $1.0) }
            let frames = layoutFrames(
                weights: ordered.map(\.1.weight), layout: layoutOf(ws), on: displayOf(ws))
            shown += zip(ordered, frames).map { Target(id: $0.0.0, frame: $0.1, visible: true) }
        }
        return shown + hidden
    }

    /// Frames for the non-floating windows of one workspace, in order.
    public func layoutFrames(weights: [Double], layout: Layout, on display: Display) -> [Rect] {
        let area = display.visibleFrame.insetBy(gap)
        guard layout.kind == .tiles, weights.count > 1 else { return weights.map { _ in area } }
        let horizontal = isHorizontal(layout, area)
        let length = tileLength(count: weights.count, area: area, horizontal: horizontal)
        let total = weights.reduce(0, +)
        var offset = horizontal ? area.x : area.y
        return weights.map { w in
            let size = length * w / total
            defer { offset += size + gap }
            return horizontal
                ? Rect(x: offset, y: area.y, width: size, height: area.height)
                : Rect(x: area.x, y: offset, width: area.width, height: size)
        }
    }

    /// The points shared by the tiles along the split axis (the area minus inner gaps).
    public func tileLength(count: Int, area: Rect, horizontal: Bool) -> Double {
        (horizontal ? area.width : area.height) - gap * Double(count - 1)
    }

    public func isHorizontal(_ layout: Layout, _ area: Rect) -> Bool {
        switch layout.orientation {
        case .horizontal: return true
        case .vertical: return false
        case .auto: return area.width >= area.height
        }
    }

    public func floatingFrame(_ record: WindowRecord, current: Rect, on display: Display) -> Rect {
        let area = display.visibleFrame
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
