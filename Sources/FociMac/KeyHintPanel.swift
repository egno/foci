import AppKit
import FociCore
import SwiftUI

/// which-key style popup: the keys of the current mode, shown at the bottom of the display when no key was pressed
/// for a moment. Never takes focus or mouse clicks, so keys keep going to the hotkeys.
@MainActor
final class KeyHintPanel {
    private let panel: NSPanel
    private var pending: DispatchWorkItem?

    var isVisible: Bool { panel.isVisible }

    init() {
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    /// Shows the hints after `delay` seconds; a later `show` or `hide` cancels it.
    func show(title: String, hints: [KeyHint], on screen: NSScreen?, after delay: TimeInterval) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.present(title: title, hints: hints, on: screen) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func hide() {
        pending?.cancel()
        pending = nil
        panel.orderOut(nil)
    }

    private func present(title: String, hints: [KeyHint], on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main, !hints.isEmpty else { return hide() }
        let area = screen.visibleFrame
        let view = NSHostingView(
            rootView: KeyHintView(title: title, hints: hints, maxWidth: area.width - 32))
        let size = view.fittingSize
        panel.contentView = view
        panel.setFrame(
            NSRect(x: area.midX - size.width / 2, y: area.minY + 12, width: size.width, height: size.height),
            display: true)
        panel.orderFrontRegardless()
    }

    /// `⌃⇧A`, `←`, `Space`: the combo as macOS menus write it.
    /// A shifted symbol key shows as its symbol: `shift-backslash` is `|` (one key on some keyboards).
    /// A range of keys stays lowercase: `a-z`.
    static func keyLabel(_ hint: KeyHint) -> String {
        guard let range = hint.range else { return keyLabel(hint.combo) }
        return modifierSymbols(hint.combo) + range
    }

    static func keyLabel(_ combo: KeyCombo) -> String {
        if combo.modifiers == [.shift], let symbol = shiftedNames[combo.key] { return symbol }
        if let held = combo.heldKey { return "Hold " + keyLabel(KeyCombo(modifiers: [], key: held)) }
        return modifierSymbols(combo) + (keyNames[combo.key] ?? combo.key.uppercased())
    }

    private static func modifierSymbols(_ combo: KeyCombo) -> String {
        let symbols: [Modifier: String] = [.ctrl: "⌃", .alt: "⌥", .shift: "⇧", .cmd: "⌘"]
        return [Modifier.ctrl, .alt, .shift, .cmd].filter(combo.modifiers.contains).compactMap { symbols[$0] }.joined()
    }

    private static let shiftedNames: [String: String] = [
        "backtick": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&", "8": "*", "9": "(",
        "0": ")", "minus": "_", "equal": "+", "leftsquarebracket": "{", "rightsquarebracket": "}", "backslash": "|",
        "semicolon": ":", "quote": "\"", "comma": "<", "period": ">", "slash": "?",
    ]

    private static let keyNames: [String: String] = [
        "minus": "-", "equal": "=", "leftsquarebracket": "[", "rightsquarebracket": "]", "backslash": "\\",
        "semicolon": ";", "quote": "'", "comma": ",", "period": ".", "slash": "/", "backtick": "`",
        "leader": "Leader", "space": "Space", "enter": "↩", "tab": "⇥", "esc": "Esc", "backspace": "⌫",
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
        "left-cmd": "‹⌘", "right-cmd": "⌘›", "left-alt": "‹⌥", "right-alt": "⌥›",
        "left-ctrl": "‹⌃", "right-ctrl": "⌃›", "left-shift": "‹⇧", "right-shift": "⇧›",
    ]
}

/// Columns filled top to bottom, as many as fit the display width; groups (`+name`) come last.
private struct KeyHintView: View {
    let title: String
    let hints: [KeyHint]
    let maxWidth: CGFloat

    private static let fontSize: CGFloat = 13
    private static let spacing: CGFloat = 24
    private static let padding: CGFloat = 14

    var body: some View {
        let keyWidth = Self.textWidth(hints.map { KeyHintPanel.keyLabel($0) }.max { $0.count < $1.count } ?? "")
        let labelWidth = min(Self.maxLabelWidth, Self.textWidth(hints.map { "+" + $0.label }.max { $0.count < $1.count } ?? ""))
        let columns = Self.columns(hints, columnWidth: keyWidth + 6 + Self.textWidth("→") + 6 + labelWidth, maxWidth: maxWidth)
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: Self.fontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: Self.spacing) {
                ForEach(columns.indices, id: \.self) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(columns[c], id: \.combo) { hint in row(hint, keyWidth: keyWidth, labelWidth: labelWidth) }
                    }
                }
            }
        }
        .padding(Self.padding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .fixedSize()
    }

    private func row(_ hint: KeyHint, keyWidth: CGFloat, labelWidth: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(KeyHintPanel.keyLabel(hint))
                .foregroundStyle(Color.accentColor)
                .frame(width: keyWidth, alignment: .trailing)
            Text("→").foregroundStyle(.tertiary)
            Text(hint.isGroup ? "+" + hint.label : hint.label)
                .foregroundStyle(hint.isGroup ? Color.purple : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: labelWidth, alignment: .leading)
        }
        .font(.system(size: Self.fontSize, design: .monospaced))
    }

    /// Longer labels are truncated.
    private static let maxLabelWidth: CGFloat = 260

    /// Fewest rows that fit the width, then the fewest columns for those rows (no empty column).
    private static func columns(_ hints: [KeyHint], columnWidth: CGFloat, maxWidth: CGFloat) -> [[KeyHint]] {
        let fit = max(1, Int((maxWidth - 2 * padding + spacing) / (columnWidth + spacing)))
        let rows = Int((Double(hints.count) / Double(min(fit, hints.count))).rounded(.up))
        return stride(from: 0, to: hints.count, by: rows).map { Array(hints[$0..<min($0 + rows, hints.count)]) }
    }

    private static func textWidth(_ s: String) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        return ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }
}
