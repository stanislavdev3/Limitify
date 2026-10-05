import Foundation
import Testing
@testable import LimitifyCore

@Suite("Codex profile discovery")
struct CodexProfileTests {
    @Test("Finds the default profile and every logged-in CODEX_HOME sibling")
    func discovery() throws {
        let home = try TemporaryHome()
        try home.makeDirectory(".codex")
        try home.makeDirectory(".codex-personal")
        try home.touch(".codex-personal/auth.json")
        try home.makeDirectory(".codex-empty")

        let profiles = CodexProfileDiscovery.discover(environment: [:], homeDirectory: home.url)

        #expect(profiles.map(\.slug) == ["default", "personal"])
        #expect(profiles[0].providerID == .codex)
        #expect(profiles[1].providerID == ProviderID(rawValue: "codex:personal"))
        #expect(profiles[1].sessionsDirectory.path.hasSuffix(".codex-personal/sessions"))
    }

    @Test("Honors CODEX_HOME for the default profile's home directory")
    func defaultHomeHonorsEnvironment() {
        let profiles = CodexProfileDiscovery.discover(
            environment: ["CODEX_HOME": "/tmp/custom-codex"],
            homeDirectory: URL(fileURLWithPath: "/tmp/home", isDirectory: true)
        )

        #expect(profiles[0].homeDirectory.path == "/tmp/custom-codex")
    }

    @Test("The default profile survives a missing CODEX_HOME directory")
    func missingDefaultDirectory() throws {
        let home = try TemporaryHome()

        let profiles = CodexProfileDiscovery.discover(environment: [:], homeDirectory: home.url)

        #expect(profiles.map(\.slug) == ["default"])
    }

    @Test("Manually added directories join discovery from any location")
    func manualDirectories() throws {
        let home = try TemporaryHome()
        try home.makeDirectory(".codex-personal")
        try home.touch(".codex-personal/auth.json")
        try home.makeDirectory("Configs/Codex Work")
        try home.touch("Configs/Codex Work/auth.json")

        let profiles = CodexProfileDiscovery.discover(
            environment: [:],
            homeDirectory: home.url,
            additionalDirectories: [
                home.url.appending(path: "Configs/Codex Work", directoryHint: .isDirectory),
                // Duplicates of discovered or already-added directories are dropped.
                home.url.appending(path: ".codex-personal", directoryHint: .isDirectory),
                home.url.appending(path: "Configs/Codex Work", directoryHint: .isDirectory),
            ]
        )

        #expect(profiles.count == 3)
        #expect(profiles.map(\.slug).prefix(2) == ["default", "personal"])
        #expect(profiles[2].slug.hasPrefix("codex-work-"))
        #expect(profiles.map(\.isManual) == [false, false, true])
    }

    @Test("Custom directory slugs are sanitized and depend only on the path")
    func slugGeneration() {
        let slug = CodexProfileDiscovery.slug(
            forCustomDirectory: URL(fileURLWithPath: "/x/Codex Work (Team)")
        )
        #expect(slug.hasPrefix("codex-work-team-"))
        #expect(slug.count == "codex-work-team-".count + 6)
        // Deterministic for the same path, distinct for same-named directories
        // elsewhere.
        #expect(slug == CodexProfileDiscovery.slug(
            forCustomDirectory: URL(fileURLWithPath: "/x/Codex Work (Team)")
        ))
        #expect(slug != CodexProfileDiscovery.slug(
            forCustomDirectory: URL(fileURLWithPath: "/y/Codex Work (Team)")
        ))
        #expect(
            CodexProfileDiscovery.slug(forCustomDirectory: URL(fileURLWithPath: "/x/..."))
                .hasPrefix("account-")
        )
    }

    @Test("A ~/.codex-default directory cannot shadow the default profile")
    func defaultSlugReserved() throws {
        let home = try TemporaryHome()
        try home.makeDirectory(".codex-default")
        try home.touch(".codex-default/auth.json")

        let profiles = CodexProfileDiscovery.discover(environment: [:], homeDirectory: home.url)

        #expect(profiles.count == 2)
        #expect(profiles[0].slug == "default")
        #expect(profiles[1].slug.hasPrefix("default-"))
        #expect(Set(profiles.map(\.providerID)).count == profiles.count)
    }

    @Test("Automatic slugs survive same-sanitizing siblings appearing or vanishing")
    func automaticSlugStability() throws {
        let home = try TemporaryHome()
        try home.makeDirectory(".codex-work-team")
        try home.touch(".codex-work-team/auth.json")

        let alone = CodexProfileDiscovery.discover(environment: [:], homeDirectory: home.url)

        try home.makeDirectory(".codex-work_team")
        try home.touch(".codex-work_team/auth.json")
        let together = CodexProfileDiscovery.discover(environment: [:], homeDirectory: home.url)

        // The clean name keeps its slug; the sanitized one carries a digest.
        #expect(alone.last?.slug == "work-team")
        #expect(together.contains { $0.slug == "work-team" })
        #expect(Set(together.map(\.slug)).count == together.count)
        let sanitizedSibling = try #require(together.first {
            $0.homeDirectory.lastPathComponent == ".codex-work_team"
        })
        #expect(sanitizedSibling.slug.hasPrefix("work-team-"))
    }

    @Test("Manual slugs survive a same-named automatic profile appearing later")
    func manualSlugStability() throws {
        let home = try TemporaryHome()
        try home.makeDirectory("Configs/personal")
        try home.touch("Configs/personal/auth.json")
        let manualDirectory = home.url.appending(path: "Configs/personal", directoryHint: .isDirectory)

        let before = try #require(CodexProfileDiscovery.discover(
            environment: [:],
            homeDirectory: home.url,
            additionalDirectories: [manualDirectory]
        ).last)

        try home.makeDirectory(".codex-personal")
        try home.touch(".codex-personal/auth.json")
        let after = try #require(CodexProfileDiscovery.discover(
            environment: [:],
            homeDirectory: home.url,
            additionalDirectories: [manualDirectory]
        ).last)

        #expect(before.slug == after.slug)
    }
}

private final class TemporaryHome {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "LimitifyCodexProfileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func makeDirectory(_ name: String) throws {
        try FileManager.default.createDirectory(
            at: url.appending(path: name, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    func touch(_ path: String) throws {
        try Data().write(to: url.appending(path: path))
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
