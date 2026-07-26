import AppKit
import Testing
@testable import LimitifyApp

@MainActor
@Suite("Menu bar usage label")
struct MenuBarUsageLabelTests {
    @Test("Segment bar represents the same remaining fraction as the percentage")
    func segmentCounts() {
        #expect(UsageBarSegments.text(for: 0) == "▱▱▱▱▱")
        #expect(UsageBarSegments.text(for: 0.73) == "▰▰▰▰▱")
        #expect(UsageBarSegments.text(for: 1) == "▰▰▰▰▰")
    }

    @Test("Segment bar clamps unexpected values")
    func clamping() {
        #expect(UsageBarSegments.filledCount(for: -1) == 0)
        #expect(UsageBarSegments.filledCount(for: 2) == 5)
    }

    @Test("OpenAI marker loads as a template image")
    func openAIMarker() throws {
        let image = try #require(OpenAIStatusIcon.image)
        #expect(image.isTemplate)
        #expect(image.size == OpenAIStatusIcon.pointSize)
    }

    @Test("Claude marker loads at menu-bar size")
    func claudeMarker() throws {
        let image = try #require(ClaudeStatusIcon.image)
        #expect(image.isTemplate)
        #expect(image.size == ClaudeStatusIcon.pointSize)
    }
}
