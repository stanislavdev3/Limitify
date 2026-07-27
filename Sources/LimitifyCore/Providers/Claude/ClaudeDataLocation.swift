import Foundation

public enum ClaudeDataLocation {
    public static func defaultCacheFile(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        cacheFile(forProfileSlug: ClaudeProfile.defaultSlug, homeDirectory: homeDirectory)
    }

    /// The default profile keeps the historical `claude-usage.json` name so
    /// status-line hooks installed by earlier versions keep feeding it.
    public static func cacheFile(
        forProfileSlug slug: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let supportDirectory = homeDirectory
            .appending(path: "Library/Application Support/Limitify", directoryHint: .isDirectory)
        let fileName = slug == ClaudeProfile.defaultSlug
            ? "claude-usage.json"
            : "claude-usage-\(slug).json"
        return supportDirectory.appending(path: fileName)
    }

    public static func defaultSettingsFile(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appending(path: ".claude", directoryHint: .isDirectory)
            .appending(path: "settings.json")
    }
}
