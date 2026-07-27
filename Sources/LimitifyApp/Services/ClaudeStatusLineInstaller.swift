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
    private let cacheFile: URL
    private let keys: Keys
    private let bundledCollector: URL?
    private let defaults: UserDefaults
    private let executableLocator: () -> URL?

    private var installedCollector: URL {
        supportDirectory.appending(path: "LimitifyClaudeStatusLine.sh")
    }

    init(
        settingsFile: URL = ClaudeDataLocation.defaultSettingsFile(),
        supportDirectory: URL = ClaudeDataLocation.defaultCacheFile().deletingLastPathComponent(),
        cacheFile: URL? = nil,
        profileSlug: String = ClaudeProfile.defaultSlug,
        bundledCollector: URL? = ClaudeStatusLineInstaller.defaultBundledCollector,
        defaults: UserDefaults = .standard,
        executableLocator: @escaping () -> URL? = { ClaudeExecutableLocator.locate() }
    ) {
        self.settingsFile = settingsFile
        self.supportDirectory = supportDirectory
        self.cacheFile = cacheFile ?? supportDirectory.appending(path: "claude-usage.json")
        keys = Keys(profileSlug: profileSlug)
        self.bundledCollector = bundledCollector
        self.defaults = defaults
        self.executableLocator = executableLocator
        refreshStatus()
    }

    convenience init(profile: ClaudeProfile) {
        self.init(
            settingsFile: profile.settingsFile,
            cacheFile: ClaudeDataLocation.cacheFile(forProfileSlug: profile.slug),
            profileSlug: profile.slug
        )
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
                defaults.set(current, forKey: keys.previousCommand)
                defaults.set(
                    try JSONSerialization.data(withJSONObject: statusLine),
                    forKey: keys.previousStatusLine
                )
                defaults.set(true, forKey: keys.hadPreviousCommand)
            } else if current == nil {
                defaults.removeObject(forKey: keys.previousCommand)
                defaults.removeObject(forKey: keys.previousStatusLine)
                defaults.set(false, forKey: keys.hadPreviousCommand)
            }

            let previous = defaults.string(forKey: keys.previousCommand) ?? ""
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
                if defaults.bool(forKey: keys.hadPreviousCommand),
                   let data = defaults.data(forKey: keys.previousStatusLine),
                   let previous = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    settings["statusLine"] = previous
                } else {
                    settings.removeValue(forKey: "statusLine")
                }
                try writeSettings(settings)
            }
            defaults.removeObject(forKey: keys.previousCommand)
            defaults.removeObject(forKey: keys.previousStatusLine)
            defaults.removeObject(forKey: keys.hadPreviousCommand)
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

    /// The default profile keeps the historical key names so backups made by
    /// earlier versions stay restorable.
    private struct Keys {
        let previousCommand: String
        let previousStatusLine: String
        let hadPreviousCommand: String

        init(profileSlug: String) {
            let suffix = profileSlug == ClaudeProfile.defaultSlug ? "" : ".\(profileSlug)"
            previousCommand = "claudePreviousStatusLineCommand" + suffix
            previousStatusLine = "claudePreviousStatusLine" + suffix
            hadPreviousCommand = "claudeHadPreviousStatusLineCommand" + suffix
        }
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
