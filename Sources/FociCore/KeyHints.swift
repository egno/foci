import Foundation

/// A row of the key hint popup: a key of the current mode and what it does.
public struct KeyHint: Equatable, Sendable {
    public let combo: KeyCombo
    public let label: String
    /// The key only enters another mode: shown as `+label` and sorted last, like which-key groups.
    public let isGroup: Bool

    public init(combo: KeyCombo, label: String, isGroup: Bool) {
        self.combo = combo; self.label = label; self.isGroup = isGroup
    }
}

extension Config {
    /// The keys of a mode as which-key shows them: keys before groups; digits and letters, then named keys
    /// (`esc`, `left`), each alphabetical; plain key before modified.
    /// `bindings` replaces the mode's own, e.g. to add built-in keys.
    /// The leader keys show as one `leader` row when they all run the same script.
    public func keyHints(for mode: String, bindings: [KeyCombo: String]? = nil) -> [KeyHint] {
        var labels = bindingLabels[mode] ?? [:]
        var bindings = bindings ?? modes[mode] ?? [:]
        if let first = leaderKeys.first, let script = bindings[first], leaderKeys.allSatisfy({ bindings[$0] == script }) {
            labels[.leader] = labels[first]
            for k in leaderKeys { bindings[k] = nil }
            bindings[.leader] = script
        }
        return bindings.map { combo, script in
            let commands = (try? Command.parseScript(script)) ?? []
            if commands.count == 1, case .mode(let target) = commands[0], target != "main" {
                return KeyHint(combo: combo, label: labels[combo] ?? modeLabels[target] ?? target, isGroup: true)
            }
            return KeyHint(combo: combo, label: labels[combo] ?? describe(script, commands), isGroup: false)
        }
        .sorted {
            ($0.isGroup ? 1 : 0, $0.combo.key.count == 1 ? 0 : 1, $0.combo.key, $0.combo.modifiers.count, $0.combo.description)
                < ($1.isGroup ? 1 : 0, $1.combo.key.count == 1 ? 0 : 1, $1.combo.key, $1.combo.modifiers.count, $1.combo.description)
        }
    }

    /// The script without `mode main`; a script that ends in a submenu names it like a group:
    /// `resize -50; mode resize` → `resize -50 +Resize`.
    func describe(_ script: String, _ commands: [Command]) -> String {
        if commands == [.mode("main")] { return "close" }
        var parts = script.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0 != "mode main" && !$0.isEmpty }
        var suffix = ""
        if parts.count > 1, case .mode(let m) = commands.last {
            parts.removeLast()
            suffix = " +" + (modeLabels[m] ?? m)
        }
        return parts.isEmpty ? script : parts.joined(separator: "; ") + suffix
    }
}
