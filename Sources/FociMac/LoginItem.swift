import Foundation
import ServiceManagement
import os

/// Keeps the login item registration in line with `start-at-login`.
@MainActor
enum LoginItem {
    private static let log = Logger(subsystem: "dev.foci", category: "app")

    /// Returns a problem to show in the menu, if any.
    static func apply(_ enabled: Bool) -> String? {
        // Only an app bundle can be a login item; `swift run` runs the bare binary.
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        let service = SMAppService.mainApp
        do {
            switch (enabled, service.status) {
            case (true, .enabled), (false, .notRegistered), (false, .notFound):
                return nil
            case (true, .requiresApproval):
                return "start-at-login: allow Foci in System Settings → General → Login Items"
            case (true, _):
                try service.register()
                log.info("registered as login item")
            case (false, _):
                try service.unregister()
                log.info("unregistered as login item")
            }
            return service.status == .requiresApproval
                ? "start-at-login: allow Foci in System Settings → General → Login Items" : nil
        } catch {
            return "start-at-login: \(error.localizedDescription)"
        }
    }
}
