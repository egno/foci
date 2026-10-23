import Foundation

public enum Direction: Equatable, Sendable {
    case next, prev
}

public enum Command: Equatable, Sendable {
    public enum LayoutChange: Equatable, Sendable { case set(LayoutKind), toggle, toggleOrientation }
    public enum ProjectTarget: Equatable, Sendable { case named(String), none, cycle(Direction), backAndForth }
    public enum WorkspaceTarget: Equatable, Sendable { case named(String), cycle(Direction), backAndForth }

    case project(ProjectTarget)
    case workspace(WorkspaceTarget)
    case moveToWorkspace(String, follow: Bool)
    /// Move the focused window to the workspace shown on the neighbouring display.
    case moveToDisplay(Direction, follow: Bool)
    case moveWorkspaceToDisplay(Direction)
    case focusDisplay(Direction)
    case focusWindow(Direction)
    /// Swap the focused window with its neighbour in the workspace order.
    case moveWindow(Direction)
    case layout(LayoutChange)
    /// Grow (+) or shrink (-) the focused tile by this many points.
    case resize(Double)
    /// Make all tiles of the focused workspace the same size.
    case balance
    /// Show the window's project and workspace and focus it (for windows picked in the menu).
    case reveal
    /// Link the focused window to a project; nil = the active project.
    case link(String?)
    case unlink
    case toggleFloat
    /// Focus the active project's window of the app, or launch it.
    case launch(app: String)
    case mode(String)
    case reloadConfig
    case exec(String)

    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public let description: String
    }

    /// Parses `cmd1; cmd2`. `exec` takes the rest of the script verbatim.
    public static func parseScript(_ script: String) throws -> [Command] {
        var result: [Command] = []
        var rest = Substring(script)
        while true {
            rest = rest.drop(while: { $0 == " " || $0 == ";" })
            if rest.isEmpty { break }
            if rest.hasPrefix("exec ") {
                result.append(.exec(String(rest.dropFirst(5)).trimmingCharacters(in: .whitespaces)))
                break
            }
            let end = rest.firstIndex(of: ";") ?? rest.endIndex
            result.append(try parse(String(rest[..<end])))
            rest = rest[end...]
        }
        return result
    }

    public static func parse(_ text: String) throws -> Command {
        let words = text.split(separator: " ").map(String.init)
        guard let name = words.first else { throw ParseError(description: "empty command") }
        let args = Array(words.dropFirst())
        func one() throws -> String {
            guard args.count == 1 else { throw ParseError(description: "'\(name)' takes exactly one argument") }
            return args[0]
        }
        func none() throws {
            if !args.isEmpty { throw ParseError(description: "'\(name)' takes no arguments") }
        }
        func direction() throws -> Direction {
            switch try one() {
            case "next": return .next
            case "prev": return .prev
            case let a: throw ParseError(description: "'\(name)': expected next|prev, got '\(a)'")
            }
        }
        switch name {
        case "project":
            switch try one() {
            case "--none": return .project(.none)
            case "next": return .project(.cycle(.next))
            case "prev": return .project(.cycle(.prev))
            case let p: return .project(.named(p))
            }
        case "project-back-and-forth": try none(); return .project(.backAndForth)
        case "workspace":
            switch try one() {
            case "next": return .workspace(.cycle(.next))
            case "prev": return .workspace(.cycle(.prev))
            case let w: return .workspace(.named(w))
            }
        case "workspace-back-and-forth": try none(); return .workspace(.backAndForth)
        case "move-to-workspace":
            let follow = args.contains("--follow")
            let rest = args.filter { $0 != "--follow" }
            guard rest.count == 1 else { throw ParseError(description: "usage: move-to-workspace [--follow] <name>") }
            return .moveToWorkspace(rest[0], follow: follow)
        case "move-to-display":
            let follow = args.contains("--follow")
            let rest = args.filter { $0 != "--follow" }
            guard rest.count == 1, let dir = ["next": Direction.next, "prev": .prev][rest[0]] else {
                throw ParseError(description: "usage: move-to-display [--follow] next|prev")
            }
            return .moveToDisplay(dir, follow: follow)
        case "move-workspace-to-display": return .moveWorkspaceToDisplay(try direction())
        case "focus-display": return .focusDisplay(try direction())
        case "focus": return .focusWindow(try direction())
        case "move": return .moveWindow(try direction())
        case "layout":
            switch try one() {
            case "tiles": return .layout(.set(.tiles))
            case "maximized": return .layout(.set(.maximized))
            case "toggle": return .layout(.toggle)
            case "toggle-orientation": return .layout(.toggleOrientation)
            case let a: throw ParseError(description: "layout: expected tiles|maximized|toggle|toggle-orientation, got '\(a)'")
            }
        case "resize":
            let a = try one()
            guard a.hasPrefix("+") || a.hasPrefix("-"), let n = Double(a) else {
                throw ParseError(description: "resize: expected +N or -N points, got '\(a)'")
            }
            return .resize(n)
        case "balance": try none(); return .balance
        case "link":
            let p = try one()
            return .link(p == "--active" ? nil : p)
        case "unlink": try none(); return .unlink
        case "reveal": try none(); return .reveal
        case "float": try none(); return .toggleFloat
        case "launch": return .launch(app: try one())
        case "mode": return .mode(try one())
        case "reload-config": try none(); return .reloadConfig
        default: throw ParseError(description: "unknown command '\(name)'")
        }
    }
}
