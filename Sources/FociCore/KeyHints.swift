import Foundation

/// A row of the key hint popup: a key of the current mode and what it does.
public struct KeyHint: Equatable, Sendable {
    public let combo: KeyCombo
    public let label: String
    /// The key only enters another mode: shown as `+label` and sorted last, like which-key groups.
    public let isGroup: Bool
    /// Several one-character keys doing the same with their own key, shown as one row: `a-z`, `a-m o-z`.
    /// `combo` is the first of them.
    public let range: String?

    public init(combo: KeyCombo, label: String, isGroup: Bool, range: String? = nil) {
        self.combo = combo; self.label = label; self.isGroup = isGroup; self.range = range
    }
}

extension Config {
    /// The keys of a mode as which-key shows them: keys before groups; digits and letters, then named keys
    /// (`esc`, `left`), each alphabetical; plain key before modified.
    /// `bindings` replaces the mode's own, e.g. to add built-in keys.
    /// The leader keys show as one `leader` row when they all run the same script, and keys that do the same
    /// with their own key (`'{workspace}' = 'workspace {workspace}'`) as one `a-z` row, and the keys of a
    /// `'{project}'` binding as one `b g i p` row.
    public func keyHints(for mode: String, bindings: [KeyCombo: String]? = nil) -> [KeyHint] {
        var labels = bindingLabels[mode] ?? [:]
        var bindings = bindings ?? modes[mode] ?? [:]
        if let first = leaderKeys.first, let script = bindings[first], leaderKeys.allSatisfy({ bindings[$0] == script }) {
            labels[.leader] = labels[first]
            for k in leaderKeys { bindings[k] = nil }
            bindings[.leader] = script
        }
        let hints = bindings.map { combo, script in
            let commands = (try? Command.parseScript(script)) ?? []
            if commands.count == 1, case .mode(let target) = commands[0], target != "main" {
                return KeyHint(combo: combo, label: labels[combo] ?? modeLabels[target] ?? target, isGroup: true)
            }
            return KeyHint(combo: combo, label: labels[combo] ?? describe(script, commands), isGroup: false)
        }
        return Self.collapseRanges(hints, projectKeys: projectKeys[mode] ?? [:]).sorted {
            ($0.isGroup ? 1 : 0, $0.combo.key.count == 1 ? 0 : 1, $0.combo.key, $0.combo.modifiers.count, $0.combo.description)
                < ($1.isGroup ? 1 : 0, $1.combo.key.count == 1 ? 0 : 1, $1.combo.key, $1.combo.modifiers.count, $1.combo.description)
        }
    }

    /// Three or more one-character keys whose labels differ only in the key itself (`workspace a`,
    /// `workspace b`, ...) become one row labelled without the key: `a-z → workspace`. Two or more keys of one
    /// `{project}` binding (`projectKeys`: key → the binding without the project) become `b g i p → project`.
    static func collapseRanges(_ hints: [KeyHint], projectKeys: [KeyCombo: String] = [:]) -> [KeyHint] {
        struct Pattern: Hashable { let modifiers: Set<Modifier>; let label: String }
        var groups: [Pattern: [KeyHint]] = [:]
        var projects: [Pattern: [KeyHint]] = [:]
        var rest: [KeyHint] = []
        for h in hints {
            if !h.isGroup, let label = projectKeys[h.combo] {
                projects[Pattern(modifiers: h.combo.modifiers, label: label), default: []].append(h)
                continue
            }
            let key = h.combo.key
            let pattern = h.label.replacingOccurrences(
                of: "(?<=^|[\\s;])\(NSRegularExpression.escapedPattern(for: key))(?=$|[\\s;])", with: "\u{0}",
                options: .regularExpression)
            if !h.isGroup, key.count == 1, pattern != h.label {
                groups[Pattern(modifiers: h.combo.modifiers, label: pattern), default: []].append(h)
            } else {
                rest.append(h)
            }
        }
        for (pattern, members) in projects {
            guard members.count >= 2 else { rest += members; continue }
            rest.append(KeyHint(combo: members.min { $0.combo.key < $1.combo.key }!.combo, label: pattern.label,
                                isGroup: false, range: ranges(members.map(\.combo.key).sorted())))
        }
        for (pattern, members) in groups {
            guard members.count >= 3 else { rest += members; continue }
            let keys = members.map(\.combo.key).sorted()
            let label = pattern.label.replacingOccurrences(of: "\u{0}", with: "")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            rest.append(KeyHint(combo: members.min { $0.combo.key < $1.combo.key }!.combo,
                                label: label.isEmpty ? pattern.label : label, isGroup: false, range: ranges(keys)))
        }
        return rest
    }

    /// `a b c d f` → `a-d f`.
    static func ranges(_ keys: [String]) -> String {
        var runs: [[String]] = []
        for k in keys {
            if let last = runs.last?.last?.unicodeScalars.first?.value, k.unicodeScalars.first?.value == last + 1 {
                runs[runs.count - 1].append(k)
            } else {
                runs.append([k])
            }
        }
        return runs.map { $0.count >= 3 ? "\($0.first!)-\($0.last!)" : $0.joined(separator: " ") }.joined(separator: " ")
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
