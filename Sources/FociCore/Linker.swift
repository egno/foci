import Foundation

/// Decides which app definition and project a window belongs to, from the config rules alone.
public struct Linker: Sendable {
    public let config: Config

    public init(config: Config) { self.config = config }

    public struct Match: Equatable, Sendable {
        public var app: AppDef?
        /// Project whose rules match the window; nil = no rule links it.
        public var project: String?
    }

    public func match(_ w: WindowFacts) -> Match {
        let candidates = config.apps.values
            .filter { $0.bundleID == nil || $0.bundleID == w.bundleID }
            .filter { $0.bundleID != nil || $0.args != nil || $0.title != nil }  // never match everything
            .sorted { $0.id < $1.id }
        var fallback: AppDef?
        for app in candidates {
            guard patternsMatch(app, w, project: nil) else { continue }
            let projects = config.projects.filter { p in
                p.ref(app.id) != nil && patternsMatch(app, w, project: p.name)
            }
            if projects.count == 1 { return Match(app: app, project: projects[0].name) }
            // No project matched: keep looking. A def without {project} (e.g. the personal Chrome) is the
            // better fallback than a per-project def whose placeholder matched nothing.
            if fallback == nil || (fallback!.isPerProject && !app.isPerProject) { fallback = app }
        }
        return Match(app: fallback, project: nil)
    }

    /// With `project == nil`, patterns containing `{project}` count as matching (checked later per project).
    func patternsMatch(_ app: AppDef, _ w: WindowFacts, project: String?) -> Bool {
        func test(_ pattern: String?, _ value: String) -> Bool {
            guard let pattern else { return true }
            if pattern.contains("{project}") {
                guard let project else { return true }
                return Self.regexMatches(
                    pattern.replacingOccurrences(of: "{project}", with: NSRegularExpression.escapedPattern(for: project)),
                    value)
            }
            return Self.regexMatches(pattern, value)
        }
        return test(app.args, w.appArgs) && test(app.title, w.title)
    }

    static func regexMatches(_ pattern: String, _ value: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        return re.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    /// The workspace a window of `app` owned by `project` opens on, if the config says.
    public func workspace(app: String?, project: String?) -> String? {
        guard let app else { return nil }
        if let project, let ws = config.project(project)?.ref(app)?.workspace { return ws }
        return config.apps[app]?.workspace
    }
}
