import Foundation
import Testing
@testable import LimitifyCore

@Suite("Codex provider composition")
struct CodexUsageProviderTests {
    @Test("Uses the preferred source when available")
    func preferredSource() async throws {
        let preferred = StubUsageProvider(result: .success(try usage(source: .appServer)))
        let fallback = StubUsageProvider(result: .success(try usage(source: .sessionJSONL)))
        let provider = CodexUsageProvider(preferred: preferred, fallback: fallback)

        let result = try await provider.fetchUsage()

        #expect(result.source.kind == .appServer)
    }

    @Test("Falls back after a preferred-source failure")
    func fallbackSource() async throws {
        let preferred = StubUsageProvider(result: .failure(CodexAppServerError.timeout))
        let fallback = StubUsageProvider(result: .success(try usage(source: .sessionJSONL)))
        let provider = CodexUsageProvider(preferred: preferred, fallback: fallback)

        let result = try await provider.fetchUsage()

        #expect(result.source.kind == .sessionJSONL)
    }

    @Test("Distinguishes a missing Codex installation from a missing fallback directory")
    func missingInstallation() async {
        let fallback = StubUsageProvider(result: .failure(CodexSessionSourceError.dataDirectoryMissing))
        let provider = CodexUsageProvider(preferred: nil, fallback: fallback)

        await #expect(throws: CodexAppServerError.executableUnavailable) {
            try await provider.fetchUsage()
        }
    }

    @Test("Preserves a no-event fallback state without a preferred source")
    func noUsageEvent() async {
        let fallback = StubUsageProvider(result: .failure(CodexSessionSourceError.noUsageEvent))
        let provider = CodexUsageProvider(preferred: nil, fallback: fallback)

        await #expect(throws: CodexSessionSourceError.noUsageEvent) {
            try await provider.fetchUsage()
        }
    }
}

private struct StubUsageProvider: UsageProvider {
    let id: ProviderID = .codex
    let result: Result<ServiceUsage, any Error>

    func fetchUsage() async throws -> ServiceUsage {
        try result.get()
    }
}

private func usage(source: UsageSourceKind) throws -> ServiceUsage {
    ServiceUsage(
        providerID: .codex,
        displayName: "Codex",
        accountLabel: "plus",
        limits: [try UsageLimit(
            id: "codex.primary",
            displayName: "Limit",
            usedFraction: 0.25,
            windowDuration: nil,
            resetAt: nil
        )],
        observedAt: .distantPast,
        source: UsageSource(
            kind: source,
            freshness: source == .appServer ? .live : .observedSnapshot
        )
    )
}
