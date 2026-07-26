import Foundation
import Testing
@testable import LimitifyCore

@Suite("Usage refresh coordinator")
struct UsageRefreshCoordinatorTests {
    @Test("Concurrent requests are coalesced")
    func coalescesRefreshes() async throws {
        let provider = CountingProvider(id: .codex, delay: .milliseconds(100))
        let coordinator = UsageRefreshCoordinator(providers: [provider])

        async let first = coordinator.refresh()
        async let second = coordinator.refresh()
        _ = await (first, second)

        #expect(await provider.fetchCount == 1)
    }

    @Test("A transient failure keeps the last successful snapshot")
    func retainsLastSuccess() async throws {
        let provider = SequenceProvider(
            id: .codex,
            results: [
                .success(try refreshUsage(providerID: .codex, used: 0.2)),
                .failure(CodexAppServerError.timeout),
            ]
        )
        let coordinator = UsageRefreshCoordinator(providers: [provider])

        _ = await coordinator.refresh(at: Date(timeIntervalSince1970: 100))
        let second = await coordinator.refresh(at: Date(timeIntervalSince1970: 200))
        let state = try #require(second[.codex])

        #expect(state.usage?.limits.first?.usedFraction == 0.2)
        #expect(state.failure == .unavailable)
        #expect(state.lastSuccessfulRefreshAt == Date(timeIntervalSince1970: 100))
        #expect(state.lastAttemptAt == Date(timeIntervalSince1970: 200))
    }

    @Test("One failed provider does not prevent another provider from updating")
    func isolatesProviderErrors() async throws {
        let otherID = ProviderID(rawValue: "other")
        let failed = SequenceProvider(
            id: .codex,
            results: [.failure(CodexSessionSourceError.noUsageEvent)]
        )
        let working = SequenceProvider(
            id: otherID,
            results: [.success(try refreshUsage(providerID: otherID, used: 0.4))]
        )
        let coordinator = UsageRefreshCoordinator(providers: [failed, working])

        let states = await coordinator.refresh()

        #expect(states[.codex]?.failure == .noUsageEvent)
        #expect(states[otherID]?.usage?.limits.first?.usedFraction == 0.4)
    }
}

private actor CountingProvider: UsageProvider {
    nonisolated let id: ProviderID
    private let delay: Duration
    private(set) var fetchCount = 0

    init(id: ProviderID, delay: Duration) {
        self.id = id
        self.delay = delay
    }

    func fetchUsage() async throws -> ServiceUsage {
        fetchCount += 1
        try await Task.sleep(for: delay)
        return try refreshUsage(providerID: id, used: 0.1)
    }
}

private actor SequenceProvider: UsageProvider {
    nonisolated let id: ProviderID
    private var results: [Result<ServiceUsage, any Error>]

    init(id: ProviderID, results: [Result<ServiceUsage, any Error>]) {
        self.id = id
        self.results = results
    }

    func fetchUsage() async throws -> ServiceUsage {
        guard !results.isEmpty else { throw CodexAppServerError.connectionClosed }
        return try results.removeFirst().get()
    }
}

private func refreshUsage(providerID: ProviderID, used: Double) throws -> ServiceUsage {
    ServiceUsage(
        providerID: providerID,
        displayName: providerID.rawValue,
        accountLabel: nil,
        limits: [try UsageLimit(
            id: "\(providerID.rawValue).primary",
            displayName: "Limit",
            usedFraction: used,
            windowDuration: nil,
            resetAt: nil
        )],
        observedAt: .distantPast,
        source: UsageSource(kind: .sessionJSONL, freshness: .observedSnapshot)
    )
}
