import Foundation

public enum CodexDataLocation {
    public static func defaultSessionsDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let codexHome: URL
        if let configuredHome = environment["CODEX_HOME"], !configuredHome.isEmpty {
            codexHome = URL(fileURLWithPath: configuredHome, isDirectory: true)
        } else {
            codexHome = homeDirectory.appending(path: ".codex", directoryHint: .isDirectory)
        }
        return codexHome.appending(path: "sessions", directoryHint: .isDirectory)
    }
}
