import Foundation
import Testing
@testable import LimitifyCore

@Suite("Claude profile discovery")
struct ClaudeProfileTests {
    @Test("Finds the default profile and every logged-in CLAUDE_CONFIG_DIR sibling")
    func discovery() throws {
        let home = try TemporaryHome()
        try home.makeDirectory(".claude")
        try home.write(".claude.json", json: [
            "oauthAccount": ["emailAddress": "work@example.com"],
        ])
        try home.makeDirectory(".claude-personal")
        try home.write(".claude-personal/.claude.json", json: [
            "oauthAccount": ["emailAddress": "personal@example.com"],
        ])
        try home.makeDirectory(".claude-empty")

        let profiles = ClaudeProfileDiscovery.discover(homeDirectory: home.url)

        #expect(profiles.map(\.slug) == ["default", "personal"])
        #expect(profiles.map(\.accountLabel) == ["work@example.com", "personal@example.com"])
        #expect(profiles[0].providerID == .claude)
        #expect(profiles[1].providerID == ProviderID(rawValue: "claude:personal"))
        #expect(profiles[1].settingsFile.path.hasSuffix(".claude-personal/settings.json"))
    }

    @Test("The default profile survives a missing state file without a label")
    func missingStateFiles() throws {
        let home = try TemporaryHome()

        let profiles = ClaudeProfileDiscovery.discover(homeDirectory: home.url)

        #expect(profiles.map(\.slug) == ["default"])
        #expect(profiles[0].accountLabel == nil)
    }

    @Test("Manually added directories join discovery from any location")
    func manualDirectories() throws {
        let home = try TemporaryHome()
        try home.makeDirectory(".claude-personal")
        try home.write(".claude-personal/.claude.json", json: [:])
        try home.makeDirectory("Configs/Claude Work")
        try home.write("Configs/Claude Work/.claude.json", json: [
            "oauthAccount": ["emailAddress": "work@example.com"],
        ])

        let profiles = ClaudeProfileDiscovery.discover(
            homeDirectory: home.url,
            additionalDirectories: [
                home.url.appending(path: "Configs/Claude Work", directoryHint: .isDirectory),
                // Duplicates of discovered or already-added directories are dropped.
                home.url.appending(path: ".claude-personal", directoryHint: .isDirectory),
                home.url.appending(path: "Configs/Claude Work", directoryHint: .isDirectory),
            ]
        )

        #expect(profiles.count == 3)
        #expect(profiles.map(\.slug).prefix(2) == ["default", "personal"])
        #expect(profiles[2].slug.hasPrefix("claude-work-"))
        #expect(profiles.map(\.isManual) == [false, false, true])
        #expect(profiles[2].accountLabel == "work@example.com")
    }

    @Test("Custom directory slugs are sanitized and depend only on the path")
    func slugGeneration() {
        let slug = ClaudeProfileDiscovery.slug(
            forCustomDirectory: URL(fileURLWithPath: "/x/Claude Work (Team)")
        )
        #expect(slug.hasPrefix("claude-work-team-"))
        #expect(slug.count == "claude-work-team-".count + 6)
        // Deterministic for the same path, distinct for same-named directories
        // elsewhere.
        #expect(slug == ClaudeProfileDiscovery.slug(
            forCustomDirectory: URL(fileURLWithPath: "/x/Claude Work (Team)")
        ))
        #expect(slug != ClaudeProfileDiscovery.slug(
            forCustomDirectory: URL(fileURLWithPath: "/y/Claude Work (Team)")
        ))
        #expect(
            ClaudeProfileDiscovery.slug(forCustomDirectory: URL(fileURLWithPath: "/x/..."))
                .hasPrefix("account-")
        )
    }

    @Test("A ~/.claude-default directory cannot shadow the default profile")
    func defaultSlugReserved() throws {
        let home = try TemporaryHome()
        try home.makeDirectory(".claude-default")
        try home.write(".claude-default/.claude.json", json: [:])

        let profiles = ClaudeProfileDiscovery.discover(homeDirectory: home.url)

        #expect(profiles.map(\.slug) == ["default", "default-2"])
        #expect(Set(profiles.map(\.providerID)).count == profiles.count)
        #expect(profiles[1].providerID == ProviderID(rawValue: "claude:default-2"))
    }

    @Test("Manual slugs survive a same-named automatic profile appearing later")
    func manualSlugStability() throws {
        let home = try TemporaryHome()
        try home.makeDirectory("Configs/personal")
        try home.write("Configs/personal/.claude.json", json: [:])
        let manualDirectory = home.url.appending(path: "Configs/personal", directoryHint: .isDirectory)

        let before = try #require(ClaudeProfileDiscovery.discover(
            homeDirectory: home.url,
            additionalDirectories: [manualDirectory]
        ).last)

        try home.makeDirectory(".claude-personal")
        try home.write(".claude-personal/.claude.json", json: [:])
        let after = try #require(ClaudeProfileDiscovery.discover(
            homeDirectory: home.url,
            additionalDirectories: [manualDirectory]
        ).last)

        #expect(before.slug == after.slug)
    }

    @Test("Per-profile caches share the historical default file name")
    func cacheLocations() {
        let home = URL(fileURLWithPath: "/synthetic/home", isDirectory: true)

        #expect(
            ClaudeDataLocation.cacheFile(forProfileSlug: "default", homeDirectory: home)
                == ClaudeDataLocation.defaultCacheFile(homeDirectory: home)
        )
        #expect(
            ClaudeDataLocation.cacheFile(forProfileSlug: "personal", homeDirectory: home)
                .lastPathComponent == "claude-usage-personal.json"
        )
    }
}

private final class TemporaryHome {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "LimitifyProfileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func makeDirectory(_ name: String) throws {
        try FileManager.default.createDirectory(
            at: url.appending(path: name, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    func write(_ path: String, json: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: json)
            .write(to: url.appending(path: path))
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
