import Foundation
import Testing
@testable import LimitifyCore

@Suite("Codex JSONL parser")
struct CodexJSONLParserTests {
    @Test("Every observed shape is accepted")
    func observedShapes() throws {
        let lines = try fixtureData("observed-shapes")
            .split(separator: UInt8(ascii: "\n"))

        #expect(lines.count == 5)

        let events = lines.compactMap { CodexJSONLParser.parseLine(Data($0)) }
        #expect(events.count == 5)
        #expect(events[0].windows.count == 2)
        #expect(events[0].windows[0].usedPercent == 27.5)
        #expect(events[0].windows[1].usedPercent == 58)
        #expect(events[3].planType == nil)
        #expect(events[4].windows.count == 1)
    }

    @Test("Malformed and partially written lines fall back to an earlier event")
    func malformedAndTruncatedLines() throws {
        let event = CodexJSONLParser.newestEvent(in: try fixtureData("malformed-and-truncated"))

        #expect(event?.windows.first?.usedPercent == 40)
        #expect(event?.planType == "plus")
    }

    @Test("Optional fields and unknown fields are tolerated; invalid percent is skipped")
    func missingFieldsAndInvalidPercent() throws {
        let event = CodexJSONLParser.newestEvent(in: try fixtureData("missing-fields-and-invalid"))

        #expect(event?.planType == nil)
        #expect(event?.windows.first?.usedPercent == 42.25)
        #expect(event?.windows.first?.windowMinutes == nil)
        #expect(event?.windows.first?.resetsAt == nil)
    }

    @Test("Non-usage records are ignored")
    func ignoresOtherRecords() {
        let line = Data(#"{"timestamp":"2026-01-10T12:00:00Z","type":"event_msg","payload":{"type":"agent_message","message":"not retained"}}"#.utf8)

        #expect(CodexJSONLParser.parseLine(line) == nil)
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
