import Foundation
import Testing
@testable import LimitifyCore

@Suite("Claude status-line source")
struct ClaudeUsageProviderTests {
    @Test("Maps official status-line rate limit windows")
    func mapsRateLimits() async throws {
        let cache = try #require(Bundle.module.url(
            forResource: "claude-statusline-rate-limits",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        let usage = try await ClaudeUsageProvider(
            cacheFile: cache,
            executableURL: URL(fileURLWithPath: "/synthetic/claude")
        ).fetchUsage()

        #expect(usage.providerID == .claude)
        #expect(usage.displayName == "Claude")
        #expect(usage.source.kind == .statusLine)
        #expect(usage.limits.count == 2)
        #expect(usage.limits[0].id == "claude.five-hour")
        #expect(usage.limits[0].remainingFraction == 0.73)
        #expect(usage.limits[0].windowDuration == 18_000)
        #expect(abs(usage.limits[1].remainingFraction - 0.41) < 0.000_001)
        #expect(usage.limits[1].windowDuration == 604_800)
    }

    @Test("Distinguishes an absent CLI from a cache awaiting its first event")
    func missingCache() async {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "claude-usage.json")

        await #expect(throws: ClaudeUsageSourceError.providerNotInstalled) {
            try await ClaudeUsageProvider(cacheFile: missing, executableURL: nil).fetchUsage()
        }
        await #expect(throws: ClaudeUsageSourceError.noUsageEvent) {
            try await ClaudeUsageProvider(
                cacheFile: missing,
                executableURL: URL(fileURLWithPath: "/synthetic/claude")
            ).fetchUsage()
        }
    }

    @Test("Decodes model-specific and unknown windows alongside the classic pair")
    func extendedWindows() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cache = directory.appending(path: "claude-usage.json")
        try Data("""
        {
            "seven_day_opus": {"used_percentage": 12, "resets_at": 1785085200},
            "seven_day_fable": {"used_percentage": 48, "resets_at": 1785085200},
            "seven_day": {"used_percentage": 59, "resets_at": 1785085200},
            "five_hour": {"used_percentage": 27, "resets_at": 1784793600},
            "extra_usage": {"used_percentage": 3, "resets_at": 1785085200},
            "session_hint": "not a window"
        }
        """.utf8).write(to: cache)

        let usage = try await ClaudeUsageProvider(
            cacheFile: cache,
            providerID: .claudeProfile("personal"),
            displayName: "Claude (personal)",
            accountLabel: "personal@example.com",
            executableURL: URL(fileURLWithPath: "/synthetic/claude")
        ).fetchUsage()

        #expect(usage.providerID == ProviderID(rawValue: "claude:personal"))
        #expect(usage.displayName == "Claude (personal)")
        #expect(usage.accountLabel == "personal@example.com")
        #expect(usage.limits.map(\.id) == [
            "claude.five-hour", "claude.seven-day", "claude.seven-day-opus",
            "claude.seven-day-fable", "claude.extra-usage",
        ])
        #expect(usage.limits.map(\.displayName) == [
            "5-hour limit", "Weekly limit", "Weekly Opus limit", "Weekly Fable limit", "Extra usage",
        ])
        #expect(usage.limits[3].windowDuration == 604_800)
        #expect(usage.limits[4].windowDuration == nil)
    }

    @Test("Boolean window values are malformed data, not 0 or 1")
    func booleanWindowValues() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cache = directory.appending(path: "claude-usage.json")
        try Data(#"{"five_hour":{"used_percentage":true,"resets_at":1785078000}}"#.utf8)
            .write(to: cache)

        await #expect(throws: ClaudeUsageSourceError.malformedData) {
            try await ClaudeUsageProvider(
                cacheFile: cache,
                executableURL: URL(fileURLWithPath: "/synthetic/claude")
            ).fetchUsage()
        }
    }

    @Test("Rejects malformed percentages without exposing raw data")
    func malformedPercentage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cache = directory.appending(path: "claude-usage.json")
        try Data(#"{"five_hour":{"used_percentage":101,"resets_at":1785078000}}"#.utf8)
            .write(to: cache)

        await #expect(throws: ClaudeUsageSourceError.malformedData) {
            try await ClaudeUsageProvider(
                cacheFile: cache,
                executableURL: URL(fileURLWithPath: "/synthetic/claude")
            ).fetchUsage()
        }
    }
}
