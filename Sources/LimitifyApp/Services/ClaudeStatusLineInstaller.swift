import Combine
import Foundation
import LimitifyCore

@MainActor
final class ClaudeStatusLineInstaller: ObservableObject {
    enum Status: Equatable {
        case notInstalled
        case ready
        case connected
        case failed(String)
    }

    @Published private(set) var status: Status = .notInstalled

    static var defaultBundledCollector: URL? {
        Bundle.main.url(forResource: "LimitifyClaudeStatusLine", withExtension: "sh")
            ?? Bundle.module.url(forResource: "LimitifyClaudeStatusLine", withExtension: "sh")
    }

    private let settingsFile: URL
    private let supportDirectory: URL
    private let bundledCollector: URL?
    private let defaults: UserDefaults
    private let executableLocator: () -> URL?

    private var installedCollector: URL {
        supportDirectory.appending(path: "LimitifyClaudeStatusLine.sh")
    }

    private var cacheFile: URL {
        supportDirectory.appending(path: "claude-usage.json")
    }

    init(
        settingsFile: URL = ClaudeDataLocation.defaultSettingsFile(),
        supportDirectory: URL = ClaudeDataLocation.defaultCacheFile().deletingLastPathComponent(),
        bundledCollector: URL? = ClaudeStatusLineInstaller.defaultBundledCollector,
        defaults: UserDefaults = .standard,
        executableLocator: @escaping () -> URL? = { ClaudeExecutableLocator.locate() }
    ) {
        self.settingsFile = settingsFile
        self.supportDirectory = supportDirectory
        self.bundledCollector = bundledCollector
        self.defaults = defaults
        self.executableLocator = executableLocator
        refreshStatus()
    }

    func refreshStatus() {
        guard executableLocator() != nil else {
            status = .notInstalled
            return
        }
        guard let command = currentStatusLineCommand() else {
            status = .ready
            return
        }
        status = command.contains("LimitifyClaudeStatusLine.sh") ? .connected : .ready
    }

    func connect() {
        do {
            guard executableLocator() != nil else {
                status = .notInstalled
                return
            }
            guard let bundledCollector else {
                throw InstallerError.collectorMissing
            }

            let fileManager = FileManager.default
            try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: installedCollector.path) {
                try fileManager.removeItem(at: installedCollector)
            }
            try fileManager.copyItem(at: bundledCollector, to: installedCollector)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: installedCollector.path
            )

            var settings = try loadSettings()
            var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
            let current = statusLine["command"] as? String
            if let current, !current.contains("LimitifyClaudeStatusLine.sh") {
                defaults.set(current, forKey: Keys.previousCommand)
                defaults.set(
                    try JSONSerialization.data(withJSONObject: statusLine),
                    forKey: Keys.previousStatusLine
                )
                defaults.set(true, forKey: Keys.hadPreviousCommand)
            } else if current == nil {
                defaults.removeObject(forKey: Keys.previousCommand)
                defaults.removeObject(forKey: Keys.previousStatusLine)
                defaults.set(false, forKey: Keys.hadPreviousCommand)
            }

            let previous = defaults.string(forKey: Keys.previousCommand) ?? ""
            let encoded = Data(previous.utf8).base64EncodedString()
            statusLine["type"] = "command"
            statusLine["command"] = [
                Self.shellQuote(installedCollector.path),
                Self.shellQuote(cacheFile.path),
                Self.shellQuote(encoded),
            ].joined(separator: " ")
            statusLine["refreshInterval"] = statusLine["refreshInterval"] ?? 60
            settings["statusLine"] = statusLine
            try writeSettings(settings)
            status = .connected
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func disconnect() {
        do {
            var settings = try loadSettings()
            if let statusLine = settings["statusLine"] as? [String: Any],
               (statusLine["command"] as? String)?.contains("LimitifyClaudeStatusLine.sh") == true {
                if defaults.bool(forKey: Keys.hadPreviousCommand),
                   let data = defaults.data(forKey: Keys.previousStatusLine),
                   let previous = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    settings["statusLine"] = previous
                } else {
                    settings.removeValue(forKey: "statusLine")
                }
                try writeSettings(settings)
            }
            defaults.removeObject(forKey: Keys.previousCommand)
            defaults.removeObject(forKey: Keys.previousStatusLine)
            defaults.removeObject(forKey: Keys.hadPreviousCommand)
            status = executableLocator() == nil ? .notInstalled : .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func currentStatusLineCommand() -> String? {
        guard let settings = try? loadSettings(),
              let statusLine = settings["statusLine"] as? [String: Any]
        else { return nil }
        return statusLine["command"] as? String
    }

    private func loadSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsFile.path) else { return [:] }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsFile))
        guard let dictionary = object as? [String: Any] else {
            throw InstallerError.invalidSettings
        }
        return dictionary
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: settingsFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsFile, options: .atomic)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private enum Keys {
        static let previousCommand = "claudePreviousStatusLineCommand"
        static let previousStatusLine = "claudePreviousStatusLine"
        static let hadPreviousCommand = "claudeHadPreviousStatusLineCommand"
    }

    private enum InstallerError: LocalizedError {
        case collectorMissing
        case invalidSettings

        var errorDescription: String? {
            switch self {
            case .collectorMissing: "The bundled Claude collector is missing."
            case .invalidSettings: "Claude settings.json is not a JSON object."
            }
        }
    }
}
