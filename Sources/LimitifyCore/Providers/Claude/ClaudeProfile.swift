import CryptoKit
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
            let name = String(directory.lastPathComponent.dropFirst(".claude-".count))
            let stateFile = directory.appending(path: ".claude.json")
            // A directory without a state file has never completed a login and
            // cannot produce usage data.
            guard !name.isEmpty, fileManager.fileExists(atPath: stateFile.path) else { continue }
            // "default" is reserved: a "~/.claude-default" directory must not
            // reuse the default profile's provider ID, which would crash the
            // refresh coordinator on duplicate keys.
            let slug = uniqueSlug(name, existing: Set(profiles.map(\.slug)))
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
                slug: slug(forCustomDirectory: standardized),
                configDirectory: standardized,
                accountLabel: accountLabel(stateFile: standardized.appending(path: ".claude.json")),
                isManual: true
            ))
        }
        return profiles
    }

    /// Slugs name cache files, provider IDs, and stored selections, so a
    /// manual profile's slug must depend only on its own path — never on which
    /// automatic profiles happen to exist, or a later-discovered `~/.claude-*`
    /// would silently remap the manual account's cache and settings. A short
    /// path digest keeps the slug deterministic and collision-free.
    static func slug(forCustomDirectory directory: URL) -> String {
        let path = directory.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        let suffix = digest.prefix(3).map { String(format: "%02x", $0) }.joined()
        return "\(sanitized(directory.lastPathComponent))-\(suffix)"
    }

    static func uniqueSlug(_ name: String, existing: Set<String>) -> String {
        let base = sanitized(name)
        var candidate = base
        var index = 2
        while existing.contains(candidate) {
            candidate = "\(base)-\(index)"
            index += 1
        }
        return candidate
    }

    private static func sanitized(_ name: String) -> String {
        let base = name.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                guard !(character == "-" && result.hasSuffix("-")) else { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return base.isEmpty ? "account" : base
    }

    static func accountLabel(stateFile: URL) -> String? {
        guard let data = try? Data(contentsOf: stateFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = object["oauthAccount"] as? [String: Any]
        else { return nil }
        return account["emailAddress"] as? String
    }
}
