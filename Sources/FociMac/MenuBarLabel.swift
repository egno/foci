import AppKit
import FociCore
import SwiftUI

/// The menu bar label as an image, after AeroSpace's experimental UI: the mode as a circled letter, the project
/// in capitals, workspaces as lettered squares (focused filled). Rendered as a template image, so the
/// menu bar tints it for light and dark mode; dimmed parts are drawn with less opacity.
@MainActor
enum MenuBarLabel {
    struct Workspace: Equatable {
        let name: String
        let focused: Bool
        let shown: Bool
    }

    struct Content: Equatable {
        /// nil in `main`.
        var mode: String?
        var project: String?
        /// Per display, main first.
        var displays: [[Workspace]]
        var warning: Bool
    }

    /// Shown workspaces only for `squares`; for `i3` also hidden ones with windows, in name order.
    static func content(_ engine: Engine, style: MenuBarStyle, warning: Bool) -> Content {
        var displays: [[Workspace]] = []
        var lastDisplay: String?
        for ws in CLIHandler(engine: engine).workspaces() where ws.shown || (style == .i3 && ws.windows > 0) {
            if ws.display != lastDisplay { displays.append([]) }
            lastDisplay = ws.display
            displays[displays.count - 1].append(Workspace(name: ws.name, focused: ws.focused, shown: ws.shown))
        }
        return Content(
            mode: engine.mode == "main" ? nil : engine.mode, project: engine.activeProject, displays: displays,
            warning: warning)
    }

    static func image(_ content: Content) -> NSImage? {
        let renderer = ImageRenderer(content: LabelView(content: content))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let cg = renderer.cgImage else { return nil }
        let image = NSImage(
            cgImage: cg, size: NSSize(width: CGFloat(cg.width) / renderer.scale, height: CGFloat(cg.height) / renderer.scale))
        image.isTemplate = true
        return image
    }

    /// SF Symbols have lettered squares and circles for a-z and 0-50.
    static func symbol(_ name: String, _ shape: String) -> String? {
        let n = name.lowercased()
        let ok = (n.count == 1 && n.first!.isASCII && n.first!.isLetter) || (Int(n).map { (0...50).contains($0) } ?? false)
        return ok ? "\(n).\(shape)" : nil
    }
}

private struct LabelView: View {
    let content: MenuBarLabel.Content

    private static let size: CGFloat = 16
    private static let font = Font.system(size: 11, weight: .bold)

    var body: some View {
        HStack(spacing: 3) {
            if let mode = content.mode {
                badge(String(mode.prefix(1)), shape: "circle", filled: false)
                Text(":").font(Self.font)
            }
            // No frame: boxes are workspaces.
            Text(content.project?.uppercased() ?? "–")
                .font(Self.font)
                .frame(height: Self.size)
                .opacity(content.project == nil ? 0.5 : 1)
            Text("›").font(Self.font).opacity(0.5).padding(.trailing, 2)
            ForEach(content.displays.indices, id: \.self) { d in
                if d > 0 { Text("|").font(Self.font).opacity(0.5) }
                ForEach(content.displays[d], id: \.name) { ws in
                    badge(ws.name.uppercased(), shape: "square", filled: ws.focused).opacity(ws.shown ? 1 : 0.45)
                }
            }
            if content.warning {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).padding(.leading, 2)
            }
        }
        .foregroundStyle(.black)
        .frame(height: 22)
        .fixedSize()
    }

    @ViewBuilder
    private func badge(_ name: String, shape: String, filled: Bool) -> some View {
        if let symbol = MenuBarLabel.symbol(name, shape) {
            Image(systemName: filled ? symbol + ".fill" : symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.size, height: Self.size)
        } else {
            box(name, filled: filled)
        }
    }

    /// Longer names: the text in a rounded box, at least square, knocked out of a filled one.
    @ViewBuilder
    private func box(_ name: String, filled: Bool) -> some View {
        let text = Text(name).font(Self.font).padding(.horizontal, 3).frame(minWidth: Self.size, minHeight: Self.size)
        if filled {
            ZStack {
                text.background(RoundedRectangle(cornerRadius: 4))
                text.blendMode(.destinationOut)
            }
            .compositingGroup()
        } else {
            text.overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(lineWidth: 1.5))
        }
    }
}
