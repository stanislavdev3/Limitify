import Foundation

/// One Claude Code installation, identified by its config directory.
/// Multiple accounts on one machine are separated with `CLAUDE_CONFIG_DIR`
/// (`~/.claude` by default, `~/.claude-<name>` by convention), and each keeps
/// its own settings, state, and rate-limit windows.
public struct ClaudeProfile: Hashable, Sendable, Identifiable {
    public static let defaultSlug = "default"

    public let slug: String
    public let configDirectory: URL
    public let accountLabel: String?
    /// True for directories the user added by hand (an arbitrary
    /// `CLAUDE_CONFIG_DIR`), which can also be removed again.
    public let isManual: Bool

    public init(slug: String, configDirectory: URL, accountLabel: String?, isManual: Bool = false) {
        self.slug = slug
        self.configDirectory = configDirectory
        self.accountLabel = accountLabel
        self.isManual = isManual
    }

    public var id: String { slug }
    public var isDefault: Bool { slug == Self.defaultSlug }
    public var providerID: ProviderID { .claudeProfile(slug) }
    public var displayName: String { isDefault ? "Claude" : "Claude (\(slug))" }
    public var settingsFile: URL { configDirectory.appending(path: "settings.json") }
}

public extension ProviderID {
    static func claudeProfile(_ slug: String) -> ProviderID {
        slug == ClaudeProfile.defaultSlug ? .claude : ProviderID(rawValue: "claude:\(slug)")
    }

    var isClaudeProvider: Bool {
        self == .claude || rawValue.hasPrefix("claude:")
    }
}

public enum ClaudeProfileDiscovery {
    /// Auto-discovery only sees `~/.claude` and the `~/.claude-<name>`
    /// convention; a `CLAUDE_CONFIG_DIR` anywhere else must be passed in as an
    /// additional directory.
    public static func discover(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        additionalDirectories: [URL] = []
    ) -> [ClaudeProfile] {
        let fileManager = FileManager.default
        var profiles = [ClaudeProfile(
            slug: ClaudeProfile.defaultSlug,
            configDirectory: homeDirectory.appending(path: ".claude", directoryHint: .isDirectory),
            // The default profile keeps its state file in the home directory,
            // not inside the config directory.
            accountLabel: accountLabel(stateFile: homeDirectory.appending(path: ".claude.json"))
        )]

        let entries = (try? fileManager.contentsOfDirectory(
            at: homeDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        let extraDirectories = entries
            .filter { $0.lastPathComponent.hasPrefix(".claude-") }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for directory in extraDirectories {
            let slug = String(directory.lastPathComponent.dropFirst(".claude-".count))
            let stateFile = directory.appending(path: ".claude.json")
            // A directory without a state file has never completed a login and
            // cannot produce usage data.
            guard !slug.isEmpty, fileManager.fileExists(atPath: stateFile.path) else { continue }
            profiles.append(ClaudeProfile(
                slug: slug,
                configDirectory: directory,
                accountLabel: accountLabel(stateFile: stateFile)
            ))
        }

        for directory in additionalDirectories {
            let standardized = directory.standardizedFileURL
            guard !profiles.contains(where: {
                $0.configDirectory.standardizedFileURL.path == standardized.path
            }) else { continue }
            profiles.append(ClaudeProfile(
                slug: slug(forCustomDirectory: standardized, existing: Set(profiles.map(\.slug))),
                configDirectory: standardized,
                accountLabel: accountLabel(stateFile: standardized.appending(path: ".claude.json")),
                isManual: true
            ))
        }
        return profiles
    }

    /// Slugs name cache files and provider IDs, so they must be filesystem-
    /// and defaults-safe, and deterministic for a given directory.
    static func slug(forCustomDirectory directory: URL, existing: Set<String>) -> String {
        var base = directory.lastPathComponent.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                guard !(character == "-" && result.hasSuffix("-")) else { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if base.isEmpty {
            base = "account"
        }
        var candidate = base
        var index = 2
        while existing.contains(candidate) {
            candidate = "\(base)-\(index)"
            index += 1
        }
        return candidate
    }

    static func accountLabel(stateFile: URL) -> String? {
        guard let data = try? Data(contentsOf: stateFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = object["oauthAccount"] as? [String: Any]
        else { return nil }
        return account["emailAddress"] as? String
    }
}
