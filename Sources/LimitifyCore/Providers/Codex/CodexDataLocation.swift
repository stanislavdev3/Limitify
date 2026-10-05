import Foundation

public enum CodexDataLocation {
    public static func defaultHomeDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let configuredHome = environment["CODEX_HOME"], !configuredHome.isEmpty {
            return URL(fileURLWithPath: configuredHome, isDirectory: true)
        }
        return homeDirectory.appending(path: ".codex", directoryHint: .isDirectory)
    }

    public static func sessionsDirectory(forHome codexHome: URL) -> URL {
        codexHome.appending(path: "sessions", directoryHint: .isDirectory)
    }

    public static func defaultSessionsDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        sessionsDirectory(forHome: defaultHomeDirectory(
            environment: environment,
            homeDirectory: homeDirectory
        ))
    }
}
