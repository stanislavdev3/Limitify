import Foundation
import Testing
@testable import LimitifyCore

@Suite("Codex app-server source")
struct CodexAppServerSourceTests {
    @Test("Prefers multi-bucket data and does not duplicate the legacy bucket")
    func multiBucketResponse() throws {
        let observedAt = Date(timeIntervalSince1970: 1_768_000_000)
        let usage = try CodexAppServerResponseDecoder.decodeUsage(
            from: fixtureData("app-server-multi-bucket"),
            observedAt: observedAt
        )

        #expect(usage.limits.count == 3)
        #expect(usage.limits.map(\.id) == ["codex.primary", "codex.secondary", "review.primary"])
        #expect(usage.limits.map(\.usedFraction) == [0.2, 0.6, 0.1])
        #expect(usage.accountLabel == "plus")
        #expect(usage.observedAt == observedAt)
        #expect(usage.source == UsageSource(kind: .appServer, freshness: .live))
    }

    @Test("Falls back to the backward-compatible bucket and accepts unknown plans")
    func legacyResponse() throws {
        let usage = try CodexAppServerResponseDecoder.decodeUsage(
            from: fixtureData("app-server-legacy"),
            observedAt: .distantPast
        )

        #expect(usage.limits.count == 1)
        #expect(usage.limits[0].usedFraction == 0.45)
        #expect(usage.accountLabel == "future_plan")
    }

    @Test("RPC errors are classified without retaining the server message")
    func rpcError() throws {
        #expect(throws: CodexAppServerError.rpcError(code: -32601)) {
            try CodexAppServerResponseDecoder.decodeUsage(
                from: fixtureData("app-server-error"),
                observedAt: .distantPast
            )
        }
    }

    @Test("Completes a real stdio handshake against a fake protocol peer")
    func stdioHandshake() async throws {
        let directory = try TemporaryAppServerDirectory()
        let executable = directory.url.appending(path: "fake-codex")
        let response = try String(decoding: fixtureData("app-server-legacy"), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let script = """
        #!/bin/sh
        IFS= read -r initialize
        printf '%s\\n' '{"id":1,"result":{"codexHome":"/tmp/fake-codex"}}'
        IFS= read -r initialized
        IFS= read -r request
        printf '%s\\n' '\(response)'
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let usage = try await CodexAppServerSource(
            executableURL: executable,
            responseTimeout: 2
        ).fetchUsage()

        #expect(usage.limits.first?.usedFraction == 0.45)
    }
}

private func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(
        forResource: name,
        withExtension: "jsonl",
        subdirectory: "Fixtures"
    ))
    return try Data(contentsOf: url)
}

private final class TemporaryAppServerDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "LimitifyAppServerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
