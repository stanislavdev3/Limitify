import Foundation
import Testing
@testable import LimitifyCore

@Suite("Usage policy")
struct UsagePolicyTests {
    @Test("Stale threshold uses the provider observation time")
    func staleThreshold() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let fresh = try makeUsage(observedAt: now.addingTimeInterval(-599), fractions: [0.2])
        let stale = try makeUsage(observedAt: now.addingTimeInterval(-601), fractions: [0.2])

        #expect(!UsagePolicy.isStale(fresh, at: now, threshold: 600))
        #expect(UsagePolicy.isStale(stale, at: now, threshold: 600))
    }

    @Test("Most constrained means the lowest remaining allowance")
    func mostConstrained() throws {
        let usage = try makeUsage(observedAt: .distantPast, fractions: [0.2, 0.75, 0.5])

        #expect(UsagePolicy.mostConstrainedLimit(in: usage)?.usedFraction == 0.75)
        #expect(UsagePolicy.mostConstrainedLimit(in: usage)?.remainingFraction == 0.25)
    }
}

private func makeUsage(observedAt: Date, fractions: [Double]) throws -> ServiceUsage {
    ServiceUsage(
        providerID: .codex,
        displayName: "Codex",
        accountLabel: nil,
        limits: try fractions.enumerated().map { index, fraction in
            try UsageLimit(
                id: "limit.\(index)",
                displayName: "Limit \(index)",
                usedFraction: fraction,
                windowDuration: nil,
                resetAt: nil
            )
        },
        observedAt: observedAt,
        source: UsageSource(kind: .sessionJSONL, freshness: .observedSnapshot)
    )
}
