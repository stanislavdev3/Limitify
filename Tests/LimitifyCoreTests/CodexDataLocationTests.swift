import Foundation
import Testing
@testable import LimitifyCore

@Suite("Codex data location")
struct CodexDataLocationTests {
    @Test("Uses CODEX_HOME when configured")
    func configuredHome() {
        let result = CodexDataLocation.defaultSessionsDirectory(
            environment: ["CODEX_HOME": "/tmp/custom-codex"],
            homeDirectory: URL(fileURLWithPath: "/tmp/home", isDirectory: true)
        )

        #expect(result.path == "/tmp/custom-codex/sessions")
    }

    @Test("Falls back to the default home directory")
    func defaultHome() {
        let result = CodexDataLocation.defaultSessionsDirectory(
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/tmp/home", isDirectory: true)
        )

        #expect(result.path == "/tmp/home/.codex/sessions")
    }
}
