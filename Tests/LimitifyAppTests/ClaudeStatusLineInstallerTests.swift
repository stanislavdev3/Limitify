import Foundation
import Testing
@testable import LimitifyApp

@MainActor
@Suite("Claude status-line installer")
struct ClaudeStatusLineInstallerTests {
    @Test("Connect preserves and disconnect restores an existing status line")
    func preservesExistingCommand() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let settingsFile = root.appending(path: ".claude/settings.json")
        let supportDirectory = root.appending(path: "Library/Application Support/Limitify")
        try FileManager.default.createDirectory(
            at: settingsFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let originalCommand = "printf 'my existing status line'"
        let original: [String: Any] = [
            "theme": "dark",
            "statusLine": ["type": "command", "command": originalCommand, "padding": 2],
        ]
        try JSONSerialization.data(withJSONObject: original).write(to: settingsFile)

        let defaults = try isolatedDefaults()
        let collector = try #require(ClaudeStatusLineInstaller.defaultBundledCollector)
        let installer = ClaudeStatusLineInstaller(
            settingsFile: settingsFile,
            supportDirectory: supportDirectory,
            bundledCollector: collector,
            defaults: defaults,
            executableLocator: { URL(fileURLWithPath: "/synthetic/claude") }
        )

        installer.connect()
        #expect(installer.status == .connected)
        let connected = try settings(at: settingsFile)
        let connectedStatusLine = try #require(connected["statusLine"] as? [String: Any])
        #expect((connectedStatusLine["command"] as? String)?.contains("LimitifyClaudeStatusLine.sh") == true)
        #expect(connected["theme"] as? String == "dark")
        let attributes = try FileManager.default.attributesOfItem(
            atPath: supportDirectory.appending(path: "LimitifyClaudeStatusLine.sh").path
        )
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o755)

        installer.disconnect()
        #expect(installer.status == .ready)
        let disconnected = try settings(at: settingsFile)
        let restored = try #require(disconnected["statusLine"] as? [String: Any])
        #expect(restored["command"] as? String == originalCommand)
        #expect(restored["padding"] as? Int == 2)
        #expect(restored["refreshInterval"] == nil)
    }

    private func settings(at url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suiteName = "LimitifyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
