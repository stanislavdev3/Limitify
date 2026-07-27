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

        #expect(profiles.map(\.slug) == ["default", "personal", "claude-work"])
        #expect(profiles.map(\.isManual) == [false, false, true])
        #expect(profiles[2].accountLabel == "work@example.com")
    }

    @Test("Custom directory slugs are sanitized and deduplicated")
    func slugGeneration() {
        #expect(
            ClaudeProfileDiscovery.slug(
                forCustomDirectory: URL(fileURLWithPath: "/x/Claude Work (Team)"),
                existing: []
            ) == "claude-work-team"
        )
        #expect(
            ClaudeProfileDiscovery.slug(
                forCustomDirectory: URL(fileURLWithPath: "/x/personal"),
                existing: ["personal", "personal-2"]
            ) == "personal-3"
        )
        #expect(
            ClaudeProfileDiscovery.slug(
                forCustomDirectory: URL(fileURLWithPath: "/x/..."),
                existing: []
            ) == "account"
        )
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
