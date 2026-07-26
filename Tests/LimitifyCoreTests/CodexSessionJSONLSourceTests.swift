import Foundation
import Testing
@testable import LimitifyCore

@Suite("Codex session JSONL source")
struct CodexSessionJSONLSourceTests {
    @Test("Maps primary and secondary limits into the common model")
    func mapsUsage() throws {
        let directory = try TemporaryDirectory()
        try copyFixture("primary-secondary", to: directory.url.appending(path: "session.jsonl"))

        let usage = try CodexSessionJSONLSource(sessionsDirectory: directory.url).loadUsage()

        #expect(usage.providerID == .codex)
        #expect(usage.accountLabel == "plus")
        #expect(usage.limits.count == 2)
        #expect(usage.limits[0].usedFraction == 0.275)
        #expect(abs(usage.limits[0].remainingFraction - 0.725) < 0.000_001)
        #expect(usage.limits[0].windowDuration == 18_000)
        #expect(usage.limits[1].usedFraction == 0.58)
        #expect(usage.limits[1].windowDuration == 604_800)
        #expect(usage.source.kind == .sessionJSONL)
        #expect(usage.source.freshness == .observedSnapshot)
    }

    @Test("Chooses newest event timestamp across files, not newest modification date")
    func choosesNewestEventAcrossFiles() throws {
        let directory = try TemporaryDirectory()
        let newerEvent = directory.url.appending(path: "older-mtime.jsonl")
        let olderEvent = directory.url.appending(path: "newer-mtime.jsonl")
        try copyFixture("selection-newer-event", to: newerEvent)
        try copyFixture("selection-older-event", to: olderEvent)

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: newerEvent.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: olderEvent.path
        )

        let usage = try CodexSessionJSONLSource(sessionsDirectory: directory.url).loadUsage()

        #expect(usage.limits.first?.usedFraction == 0.61)
    }

    @Test("A tail beginning mid-line discards the fragment and finds the next event")
    func tailBoundary() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "large.jsonl")
        let padding = #"{"type":"event_msg","payload":{"type":"agent_message","message":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}}"#
        let usage = #"{"timestamp":"2026-01-10T15:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":70.0,"window_minutes":300,"resets_at":1768064400}}}}"#
        try Data("\(padding)\n\(usage)\n".utf8).write(to: file)

        let source = CodexSessionJSONLSource(
            sessionsDirectory: directory.url,
            candidateLimit: 4,
            initialTailBytes: usage.utf8.count + 16,
            maximumTailBytes: usage.utf8.count + 16
        )

        #expect(try source.loadUsage().limits.first?.usedFraction == 0.7)
    }

    @Test("Missing directory and no usage event are distinct errors")
    func sourceErrors() throws {
        let directory = try TemporaryDirectory()
        let missing = directory.url.appending(path: "missing")

        #expect(throws: CodexSessionSourceError.dataDirectoryMissing) {
            try CodexSessionJSONLSource(sessionsDirectory: missing).loadUsage()
        }

        try Data(#"{"type":"event_msg","payload":{"type":"agent_message"}}"#.utf8)
            .write(to: directory.url.appending(path: "session.jsonl"))

        #expect(throws: CodexSessionSourceError.noUsageEvent) {
            try CodexSessionJSONLSource(sessionsDirectory: directory.url).loadUsage()
        }
    }

    @Test("A malformed usage record is distinct from no usage event")
    func malformedUsageRecord() throws {
        let directory = try TemporaryDirectory()
        try Data(#"{"payload":{"rate_limits":{"primary":{"used_percent":20}"#.utf8)
            .write(to: directory.url.appending(path: "session.jsonl"))

        #expect(throws: CodexSessionSourceError.malformedData) {
            try CodexSessionJSONLSource(sessionsDirectory: directory.url).loadUsage()
        }
    }
}

private func copyFixture(_ name: String, to destination: URL) throws {
    let source = try #require(Bundle.module.url(
        forResource: name,
        withExtension: "jsonl",
        subdirectory: "Fixtures"
    ))
    try FileManager.default.copyItem(at: source, to: destination)
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "LimitifyTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
