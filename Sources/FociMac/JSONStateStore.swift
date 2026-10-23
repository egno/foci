import FociCore
import Foundation
import os

/// Persists `State` to `~/Library/Application Support/Foci/state.json`.
@MainActor
public final class JSONStateStore: StateStore {
    private let url: URL
    private let log = Logger(subsystem: "dev.foci", category: "state")

    public init(url: URL = JSONStateStore.defaultURL) { self.url = url }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Foci/state.json")
    }

    public func load() -> State? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(State.self, from: data)
        } catch {
            log.error("ignoring unreadable state: \(error)")
            return nil
        }
    }

    public func save(_ state: State) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: url, options: .atomic)
        } catch {
            log.error("can't save state: \(error)")
        }
    }
}
