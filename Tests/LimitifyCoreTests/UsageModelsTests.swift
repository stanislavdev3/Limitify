import Foundation
import Testing
@testable import LimitifyCore

@Suite("Usage models")
struct UsageModelsTests {
    @Test("Remaining fraction is derived from used fraction")
    func remainingFraction() throws {
        let limit = try UsageLimit(
            id: "codex.primary",
            displayName: "5-hour limit",
            usedFraction: 0.27,
            windowDuration: 18_000,
            resetAt: nil
        )

        #expect(limit.remainingFraction == 0.73)
    }

    @Test("Invalid fractions are rejected")
    func invalidFraction() {
        #expect(throws: UsageModelError.invalidUsedFraction) {
            try UsageLimit(
                id: "codex.primary",
                displayName: "Limit",
                usedFraction: .infinity,
                windowDuration: nil,
                resetAt: nil
            )
        }
        #expect(throws: UsageModelError.invalidUsedFraction) {
            try UsageLimit(
                id: "codex.primary",
                displayName: "Limit",
                usedFraction: 1.01,
                windowDuration: nil,
                resetAt: nil
            )
        }
    }
}
