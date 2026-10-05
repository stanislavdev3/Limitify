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

    private let codexProfiles = [
        CodexProfile(
            slug: CodexProfile.defaultSlug,
            homeDirectory: URL(fileURLWithPath: "/synthetic/.codex", isDirectory: true)
        ),
    ]

    @Test("Defaults match the product specification")
    func defaults() throws {
        let defaults = try isolatedDefaults()
        let settings = makeSettings(defaults: defaults)

        #expect(settings.refreshInterval == 60)
        #expect(settings.staleThreshold == 600)
        #expect(settings.codexEnabled)
        #expect(settings.claudeEnabled)
        #expect(settings.displayProviderID == .codex)
    }

    @Test("Preferences persist in UserDefaults")
    func persistence() throws {
        let defaults = try isolatedDefaults()
        let settings = makeSettings(defaults: defaults)
        settings.refreshInterval = 300
        settings.staleThreshold = 1_800
        settings.codexEnabled = false
        settings.displayProviderID = .claudeProfile("personal")

        let restored = makeSettings(defaults: defaults)
        #expect(restored.refreshInterval == 300)
        #expect(restored.staleThreshold == 1_800)
        #expect(!restored.codexEnabled)
        #expect(restored.claudeEnabled)
        #expect(restored.displayProviderID == .claudeProfile("personal"))
    }

    @Test("Every enabled provider gets a selectable entry, one per Claude profile")
    func enabledProviders() throws {
        let defaults = try isolatedDefaults()
        let settings = makeSettings(defaults: defaults)

        #expect(settings.enabledDisplayProviders.map(\.providerID) == [
            .codex, .claude, .claudeProfile("personal"),
        ])
        #expect(settings.enabledDisplayProviders[2].accountLabel == "personal@example.com")

        settings.claudeEnabled = false
        #expect(settings.enabledDisplayProviders.map(\.providerID) == [.codex])
    }

    @Test("Every enabled Codex profile gets its own selectable entry")
    func enabledCodexProviders() throws {
        let defaults = try isolatedDefaults()
        let twoCodexProfiles = codexProfiles + [
            CodexProfile(
                slug: "work",
                homeDirectory: URL(fileURLWithPath: "/synthetic/.codex-work", isDirectory: true)
            ),
        ]
        let settings = makeSettings(defaults: defaults, codexProfiles: twoCodexProfiles)

        #expect(settings.enabledDisplayProviders.map(\.providerID) == [
            .codex, ProviderID(rawValue: "codex:work"), .claude, .claudeProfile("personal"),
        ])

        settings.codexEnabled = false
        #expect(settings.enabledDisplayProviders.map(\.providerID) == [.claude, .claudeProfile("personal")])
    }

    @Test("Disabling the displayed provider switches the menu bar to a remaining one")
    func displayProviderReassignment() throws {
        let defaults = try isolatedDefaults()
        let settings = makeSettings(defaults: defaults)
        settings.displayProviderID = .codex

        settings.codexEnabled = false
        #expect(settings.displayProviderID == .claude)

        settings.claudeEnabled = false
        #expect(settings.displayProviderID == .claude)
    }

    @Test("Custom labels and tints persist per Claude profile and feed display entries")
    func customizations() throws {
        let defaults = try isolatedDefaults()
        let settings = makeSettings(defaults: defaults)
        settings.setClaudeCustomization(
            ProfileCustomization(label: "Личный", tint: .teal),
            for: "personal"
        )

        let personal = settings.enabledDisplayProviders[2]
        #expect(personal.displayName == "Личный")
        #expect(personal.tint == .teal)
        #expect(settings.enabledDisplayProviders[1].tint == ProfileTint.none)

        let restored = makeSettings(defaults: defaults)
        #expect(restored.claudeCustomization(for: "personal").label == "Личный")
        #expect(restored.claudeCustomization(for: "personal").tint == .teal)

        restored.setClaudeCustomization(ProfileCustomization(), for: "personal")
        #expect(restored.claudeProfileCustomizations.isEmpty)
    }

    @Test("Custom labels and tints persist per Codex profile independently of Claude")
    func codexCustomizations() throws {
        let defaults = try isolatedDefaults()
        let settings = makeSettings(defaults: defaults)
        settings.setCodexCustomization(
            ProfileCustomization(label: "Work", tint: .orange),
            for: CodexProfile.defaultSlug
        )
        // Same slug namespace used by a Claude profile must not collide.
        settings.setClaudeCustomization(
            ProfileCustomization(label: "Default Claude label"),
            for: CodexProfile.defaultSlug
        )

        #expect(settings.enabledDisplayProviders[0].displayName == "Work")
        #expect(settings.enabledDisplayProviders[0].tint == .orange)

        let restored = makeSettings(defaults: defaults)
        #expect(restored.codexCustomization(for: CodexProfile.defaultSlug).label == "Work")
        #expect(restored.claudeCustomization(for: CodexProfile.defaultSlug).label == "Default Claude label")
    }

    @Test("Group assignment crosses providers and persists; ungrouped accounts default to none")
    func groupAssignment() throws {
        let defaults = try isolatedDefaults()
        let settings = makeSettings(defaults: defaults)

        settings.setCodexCustomization(ProfileCustomization(group: .work), for: CodexProfile.defaultSlug)
        settings.setClaudeCustomization(ProfileCustomization(group: .personal), for: "personal")

        #expect(settings.enabledDisplayProviders.map(\.group) == [.work, .none, .personal])

        let restored = makeSettings(defaults: defaults)
        #expect(restored.enabledDisplayProviders.map(\.group) == [.work, .none, .personal])

        restored.setCodexCustomization(ProfileCustomization(), for: CodexProfile.defaultSlug)
        #expect(restored.enabledDisplayProviders[0].group == .none)
    }

    @Test("Labels are stored verbatim but whitespace-only values display as unset")
    func labelNormalization() throws {
        let defaults = try isolatedDefaults()
        let settings = makeSettings(defaults: defaults)

        settings.setClaudeCustomization(ProfileCustomization(label: "  Work  "), for: "personal")
        #expect(settings.claudeCustomization(for: "personal").label == "  Work  ")
        #expect(settings.enabledDisplayProviders[2].displayName == "Work")

        settings.setClaudeCustomization(ProfileCustomization(label: "   ", tint: .blue), for: "personal")
        #expect(settings.enabledDisplayProviders[2].displayName == "Claude (personal)")
    }

    @Test("Manually added Claude config directories persist and can be removed")
    func manualDirectories() throws {
        let defaults = try isolatedDefaults()
        var receivedDirectories: [URL] = []
        let discovery: ([URL]) -> [ClaudeProfile] = { directories in
            receivedDirectories = directories
            return self.profiles
        }
        let settings = makeSettings(defaults: defaults, claudeProfileDiscovery: discovery)
        let directory = URL(fileURLWithPath: "/synthetic/configs/claude-work", isDirectory: true)

        settings.addClaudeProfileDirectory(directory)
        settings.addClaudeProfileDirectory(directory)
        #expect(settings.claudeProfileDirectories == [directory.path])
        #expect(receivedDirectories == [directory])

        let restored = makeSettings(defaults: defaults, claudeProfileDiscovery: discovery)
        #expect(restored.claudeProfileDirectories == [directory.path])

        restored.removeClaudeProfileDirectory(ClaudeProfile(
            slug: "claude-work",
            configDirectory: directory,
            accountLabel: nil,
            isManual: true
        ))
        #expect(restored.claudeProfileDirectories.isEmpty)
    }

    @Test("Manually added Codex config directories persist and can be removed")
    func manualCodexDirectories() throws {
        let defaults = try isolatedDefaults()
        var receivedDirectories: [URL] = []
        let discovery: ([URL]) -> [CodexProfile] = { directories in
            receivedDirectories = directories
            return self.codexProfiles
        }
        let settings = makeSettings(defaults: defaults, codexProfileDiscovery: discovery)
        let directory = URL(fileURLWithPath: "/synthetic/configs/codex-work", isDirectory: true)

        settings.addCodexProfileDirectory(directory)
        settings.addCodexProfileDirectory(directory)
        #expect(settings.codexProfileDirectories == [directory.path])
        #expect(receivedDirectories == [directory])

        let restored = makeSettings(defaults: defaults, codexProfileDiscovery: discovery)
        #expect(restored.codexProfileDirectories == [directory.path])

        restored.removeCodexProfileDirectory(CodexProfile(
            slug: "codex-work",
            homeDirectory: directory,
            isManual: true
        ))
        #expect(restored.codexProfileDirectories.isEmpty)
    }

    @Test("A stored selection pointing at a vanished profile falls back at launch")
    func staleSelectionFallsBack() throws {
        let defaults = try isolatedDefaults()
        defaults.set("claude:gone", forKey: "displayProvider")
        let settings = makeSettings(defaults: defaults)

        #expect(settings.displayProviderID == .codex)
    }

    /// Every test wires both discovery closures to fixed fixtures so
    /// `enabledDisplayProviders` never depends on the machine actually
    /// running the suite.
    private func makeSettings(
        defaults: UserDefaults,
        codexProfiles: [CodexProfile]? = nil,
        claudeProfileDiscovery: (([URL]) -> [ClaudeProfile])? = nil,
        codexProfileDiscovery: (([URL]) -> [CodexProfile])? = nil
    ) -> AppSettings {
        let claudeFixture = self.profiles
        let codexFixture = codexProfiles ?? self.codexProfiles
        return AppSettings(
            defaults: defaults,
            claudeProfileDiscovery: claudeProfileDiscovery ?? { _ in claudeFixture },
            codexProfileDiscovery: codexProfileDiscovery ?? { _ in codexFixture }
        )
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suiteName = "LimitifyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
