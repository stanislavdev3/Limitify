import Foundation

public enum ClaudeDataLocation {
    public static func defaultCacheFile(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appending(path: "Library/Application Support/Limitify", directoryHint: .isDirectory)
            .appending(path: "claude-usage.json")
    }

    public static func defaultSettingsFile(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appending(path: ".claude", directoryHint: .isDirectory)
            .appending(path: "settings.json")
    }
}
