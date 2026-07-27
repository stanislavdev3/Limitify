import Foundation
import LimitifyCore
import Testing
@testable import LimitifyApp

@MainActor
@Suite("Application settings")
struct AppSettingsTests {
    private let profiles = [
        ClaudeProfile(
            slug: ClaudeProfile.defaultSlug,
            configDirectory: URL(fileURLWithPath: "/synthetic/.claude", isDirectory: true),
            accountLabel: "work@example.com"
        ),
        ClaudeProfile(
            slug: "personal",
            configDirectory: URL(fileURLWithPath: "/synthetic/.claude-personal", isDirectory: true),
            accountLabel: "personal@example.com"
        ),
    ]

    @Test("Defaults match the product specification")
    func defaults() throws {
        let defaults = try isolatedDefaults()
        let settings = AppSettings(defaults: defaults, profileDiscovery: { _ in self.profiles })

        #expect(settings.refreshInterval == 60)
        #expect(settings.staleThreshold == 600)
        #expect(settings.codexEnabled)
        #expect(settings.claudeEnabled)
        #expect(settings.displayProviderID == .codex)
        #expect(settings.codexSessionsPath.hasSuffix("/.codex/sessions"))
    }

    @Test("Preferences persist in UserDefaults")
    func persistence() throws {
        let defaults = try isolatedDefaults()
        let settings = AppSettings(defaults: defaults, profileDiscovery: { _ in self.profiles })
        settings.refreshInterval = 300
        settings.staleThreshold = 1_800
        settings.codexEnabled = false
        settings.displayProviderID = .claudeProfile("personal")
        settings.codexSessionsPath = "/tmp/synthetic-codex/sessions"

        let restored = AppSettings(defaults: defaults, profileDiscovery: { _ in self.profiles })
        #expect(restored.refreshInterval == 300)
        #expect(restored.staleThreshold == 1_800)
        #expect(!restored.codexEnabled)
        #expect(restored.claudeEnabled)
        #expect(restored.displayProviderID == .claudeProfile("personal"))
        #expect(restored.codexSessionsPath == "/tmp/synthetic-codex/sessions")
    }

    @Test("Every enabled provider gets a selectable entry, one per Claude profile")
    func enabledProviders() throws {
        let defaults = try isolatedDefaults()
        let settings = AppSettings(defaults: defaults, profileDiscovery: { _ in self.profiles })

        #expect(settings.enabledDisplayProviders.map(\.providerID) == [
            .codex, .claude, .claudeProfile("personal"),
        ])
        #expect(settings.enabledDisplayProviders[2].accountLabel == "personal@example.com")

        settings.claudeEnabled = false
        #expect(settings.enabledDisplayProviders.map(\.providerID) == [.codex])
    }

    @Test("Disabling the displayed provider switches the menu bar to a remaining one")
    func displayProviderReassignment() throws {
        let defaults = try isolatedDefaults()
        let settings = AppSettings(defaults: defaults, profileDiscovery: { _ in self.profiles })
        settings.displayProviderID = .codex

        settings.codexEnabled = false
        #expect(settings.displayProviderID == .claude)

        settings.claudeEnabled = false
        #expect(settings.displayProviderID == .claude)
    }

    @Test("Custom labels and tints persist per profile and feed display entries")
    func customizations() throws {
        let defaults = try isolatedDefaults()
        let settings = AppSettings(defaults: defaults, profileDiscovery: { _ in self.profiles })
        settings.setCustomization(
            ClaudeProfileCustomization(label: "Личный", tint: .teal),
            for: "personal"
        )

        let personal = settings.enabledDisplayProviders[2]
        #expect(personal.displayName == "Личный")
        #expect(personal.tint == .teal)
        #expect(settings.enabledDisplayProviders[1].tint == ProfileTint.none)

        let restored = AppSettings(defaults: defaults, profileDiscovery: { _ in self.profiles })
        #expect(restored.customization(for: "personal").label == "Личный")
        #expect(restored.customization(for: "personal").tint == .teal)

        restored.setCustomization(ClaudeProfileCustomization(), for: "personal")
        #expect(restored.claudeProfileCustomizations.isEmpty)
    }

    @Test("Labels are stored verbatim but whitespace-only values display as unset")
    func labelNormalization() throws {
        let defaults = try isolatedDefaults()
        let settings = AppSettings(defaults: defaults, profileDiscovery: { _ in self.profiles })

        settings.setCustomization(ClaudeProfileCustomization(label: "  Work  "), for: "personal")
        #expect(settings.customization(for: "personal").label == "  Work  ")
        #expect(settings.enabledDisplayProviders[2].displayName == "Work")

        settings.setCustomization(ClaudeProfileCustomization(label: "   ", tint: .blue), for: "personal")
        #expect(settings.enabledDisplayProviders[2].displayName == "Claude (personal)")
    }

    @Test("Manually added config directories persist and can be removed")
    func manualDirectories() throws {
        let defaults = try isolatedDefaults()
        var receivedDirectories: [URL] = []
        let discovery: ([URL]) -> [ClaudeProfile] = { directories in
            receivedDirectories = directories
            return self.profiles
        }
        let settings = AppSettings(defaults: defaults, profileDiscovery: discovery)
        let directory = URL(fileURLWithPath: "/synthetic/configs/claude-work", isDirectory: true)

        settings.addClaudeProfileDirectory(directory)
        settings.addClaudeProfileDirectory(directory)
        #expect(settings.claudeProfileDirectories == [directory.path])
        #expect(receivedDirectories == [directory])

        let restored = AppSettings(defaults: defaults, profileDiscovery: discovery)
        #expect(restored.claudeProfileDirectories == [directory.path])

        restored.removeClaudeProfileDirectory(ClaudeProfile(
            slug: "claude-work",
            configDirectory: directory,
            accountLabel: nil,
            isManual: true
        ))
        #expect(restored.claudeProfileDirectories.isEmpty)
    }

    @Test("A stored selection pointing at a vanished profile falls back at launch")
    func staleSelectionFallsBack() throws {
        let defaults = try isolatedDefaults()
        defaults.set("claude:gone", forKey: "displayProvider")
        let settings = AppSettings(defaults: defaults, profileDiscovery: { _ in self.profiles })

        #expect(settings.displayProviderID == .codex)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suiteName = "LimitifyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
