import Foundation
import Testing
@testable import LimitifyApp

@MainActor
@Suite("Application settings")
struct AppSettingsTests {
    @Test("Defaults match the product specification")
    func defaults() throws {
        let defaults = try isolatedDefaults()
        let settings = AppSettings(defaults: defaults)

        #expect(settings.refreshInterval == 60)
        #expect(settings.staleThreshold == 600)
        #expect(settings.codexEnabled)
        #expect(settings.codexSessionsPath.hasSuffix("/.codex/sessions"))
    }

    @Test("Preferences persist in UserDefaults")
    func persistence() throws {
        let defaults = try isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.refreshInterval = 300
        settings.staleThreshold = 1_800
        settings.codexEnabled = false
        settings.codexSessionsPath = "/tmp/synthetic-codex/sessions"

        let restored = AppSettings(defaults: defaults)
        #expect(restored.refreshInterval == 300)
        #expect(restored.staleThreshold == 1_800)
        #expect(!restored.codexEnabled)
        #expect(restored.codexSessionsPath == "/tmp/synthetic-codex/sessions")
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suiteName = "LimitifyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
