import CryptoKit
import Foundation

/// One Codex installation, identified by its `CODEX_HOME` directory.
/// Multiple accounts on one machine are separated with `CODEX_HOME`
/// (`~/.codex` by default, `~/.codex-<name>` by convention), and each keeps
/// its own credentials, config, and sessions.
public struct CodexProfile: Hashable, Sendable, Identifiable {
    public static let defaultSlug = "default"

    public let slug: String
    public let homeDirectory: URL
    public let isManual: Bool

    public init(slug: String, homeDirectory: URL, isManual: Bool = false) {
        self.slug = slug
        self.homeDirectory = homeDirectory
        self.isManual = isManual
    }

    public var id: String { slug }
    public var isDefault: Bool { slug == Self.defaultSlug }
    public var providerID: ProviderID { .codexProfile(slug) }
    public var displayName: String { isDefault ? "Codex" : "Codex (\(slug))" }
    public var sessionsDirectory: URL { CodexDataLocation.sessionsDirectory(forHome: homeDirectory) }
    /// Credentials live here; Limitify only ever checks for the file's
    /// existence to tell a logged-in account from an empty directory, never
    /// reads its contents.
    public var authFile: URL { homeDirectory.appending(path: "auth.json") }
}

public extension ProviderID {
    static func codexProfile(_ slug: String) -> ProviderID {
        slug == CodexProfile.defaultSlug ? .codex : ProviderID(rawValue: "codex:\(slug)")
    }

    var isCodexProvider: Bool {
        self == .codex || rawValue.hasPrefix("codex:")
    }
}

public enum CodexProfileDiscovery {
    /// Auto-discovery only sees the default `CODEX_HOME` (or `~/.codex`) and
    /// the `~/.codex-<name>` convention; a `CODEX_HOME` anywhere else must be
    /// passed in as an additional directory.
    public static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        additionalDirectories: [URL] = []
    ) -> [CodexProfile] {
        let fileManager = FileManager.default
        var profiles = [CodexProfile(
            slug: CodexProfile.defaultSlug,
            homeDirectory: CodexDataLocation.defaultHomeDirectory(
                environment: environment,
                homeDirectory: homeDirectory
            )
        )]

        let entries = (try? fileManager.contentsOfDirectory(
            at: homeDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        let extraDirectories = entries
            .filter { $0.lastPathComponent.hasPrefix(".codex-") }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for directory in extraDirectories {
            let name = String(directory.lastPathComponent.dropFirst(".codex-".count))
            // A directory without credentials has never completed a login and
            // cannot produce usage data.
            guard !name.isEmpty,
                  fileManager.fileExists(atPath: directory.appending(path: "auth.json").path)
            else { continue }
            profiles.append(CodexProfile(
                slug: automaticSlug(name: name, directory: directory),
                homeDirectory: directory
            ))
        }

        for directory in additionalDirectories {
            let standardized = directory.standardizedFileURL
            guard !profiles.contains(where: {
                $0.homeDirectory.standardizedFileURL.path == standardized.path
            }) else { continue }
            profiles.append(CodexProfile(
                slug: slug(forCustomDirectory: standardized),
                homeDirectory: standardized,
                isManual: true
            ))
        }
        return profiles
    }

    // Slugs name cache lookups, provider IDs, and stored selections, so every
    // slug must depend only on its own directory — never on which other
    // profiles happen to exist, or adding/removing one account would silently
    // remap another account's provider ID.

    /// A `~/.codex-<name>` directory keeps `<name>` verbatim when it is
    /// already a clean slug (distinct directory names then guarantee distinct
    /// slugs). A name that sanitization would alter — or the reserved
    /// `default`, whose provider ID belongs to `~/.codex` — gets a path
    /// digest instead, since two altered names can collide.
    static func automaticSlug(name: String, directory: URL) -> String {
        let base = sanitized(name)
        guard base == name, base != CodexProfile.defaultSlug else {
            return "\(base)-\(pathDigest(directory))"
        }
        return base
    }

    /// Manual directories always carry the digest: their bare names live in a
    /// different namespace than `~/.codex-*` and could otherwise collide with
    /// an automatic slug.
    static func slug(forCustomDirectory directory: URL) -> String {
        "\(sanitized(directory.lastPathComponent))-\(pathDigest(directory))"
    }

    private static func pathDigest(_ directory: URL) -> String {
        let digest = SHA256.hash(data: Data(directory.standardizedFileURL.path.utf8))
        return digest.prefix(3).map { String(format: "%02x", $0) }.joined()
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
}
