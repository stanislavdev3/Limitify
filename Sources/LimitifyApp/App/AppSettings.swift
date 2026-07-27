import Combine
import Foundation
import LimitifyCore

/// Muted card tints that sit on top of the standard quaternary background.
/// Rendering maps them to system colors at low opacity so they adapt to both
/// appearances instead of shouting.
enum ProfileTint: String, CaseIterable, Codable {
    case none
    case blue
    case purple
    case teal
    case green
    case orange
    case pink
    case graphite
}

struct ClaudeProfileCustomization: Codable, Equatable {
    var label: String?
    var tint: ProfileTint = .none

    var isEmpty: Bool { label == nil && tint == .none }

    /// The label is stored exactly as typed — a transforming TextField binding
    /// rewrites the field on every keystroke and breaks the cursor — so
    /// whitespace-only values are filtered here, at the point of use.
    var normalizedLabel: String? {
        guard let label else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct DisplayProvider: Identifiable, Hashable {
    enum Kind: Hashable {
        case codex
        case claude
    }

    let providerID: ProviderID
    let kind: Kind
    let displayName: String
    let accountLabel: String?
    let tint: ProfileTint

    var id: String { providerID.rawValue }

    static let codex = DisplayProvider(
        providerID: .codex,
        kind: .codex,
        displayName: "Codex",
        accountLabel: nil,
        tint: .none
    )

    static func claude(
        _ profile: ClaudeProfile,
        customization: ClaudeProfileCustomization
    ) -> DisplayProvider {
        DisplayProvider(
            providerID: profile.providerID,
            kind: .claude,
            displayName: customization.normalizedLabel ?? profile.displayName,
            accountLabel: profile.accountLabel,
            tint: customization.tint
        )
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let refreshIntervalOptions: [TimeInterval] = [30, 60, 120, 300, 600]
    static let staleThresholdOptions: [TimeInterval] = [300, 600, 1_800, 3_600]

    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    @Published var staleThreshold: TimeInterval {
        didSet { defaults.set(staleThreshold, forKey: Keys.staleThreshold) }
    }

    @Published var codexSessionsPath: String {
        didSet { defaults.set(codexSessionsPath, forKey: Keys.codexSessionsPath) }
    }

    @Published var codexEnabled: Bool {
        didSet {
            defaults.set(codexEnabled, forKey: Keys.codexEnabled)
            reassignDisplayProviderIfDisabled()
        }
    }

    @Published var claudeEnabled: Bool {
        didSet {
            defaults.set(claudeEnabled, forKey: Keys.claudeEnabled)
            reassignDisplayProviderIfDisabled()
        }
    }

    @Published var displayProviderID: ProviderID {
        didSet { defaults.set(displayProviderID.rawValue, forKey: Keys.displayProvider) }
    }

    @Published private(set) var claudeProfiles: [ClaudeProfile]
    @Published private(set) var claudeProfileDirectories: [String]
    @Published private(set) var claudeProfileCustomizations: [String: ClaudeProfileCustomization]

    private let defaults: UserDefaults
    private let profileDiscovery: ([URL]) -> [ClaudeProfile]

    init(
        defaults: UserDefaults = .standard,
        profileDiscovery: @escaping ([URL]) -> [ClaudeProfile] = {
            ClaudeProfileDiscovery.discover(additionalDirectories: $0)
        }
    ) {
        self.defaults = defaults
        self.profileDiscovery = profileDiscovery
        defaults.register(defaults: [
            Keys.refreshInterval: 60.0,
            Keys.staleThreshold: 600.0,
            Keys.codexSessionsPath: CodexDataLocation.defaultSessionsDirectory().path,
            Keys.codexEnabled: true,
            Keys.claudeEnabled: true,
            Keys.displayProvider: ProviderID.codex.rawValue,
        ])

        refreshInterval = Self.validated(
            defaults.double(forKey: Keys.refreshInterval),
            options: Self.refreshIntervalOptions,
            fallback: 60
        )
        staleThreshold = Self.validated(
            defaults.double(forKey: Keys.staleThreshold),
            options: Self.staleThresholdOptions,
            fallback: 600
        )
        codexSessionsPath = defaults.string(forKey: Keys.codexSessionsPath)
            ?? CodexDataLocation.defaultSessionsDirectory().path
        codexEnabled = defaults.bool(forKey: Keys.codexEnabled)
        claudeEnabled = defaults.bool(forKey: Keys.claudeEnabled)
        let directories = defaults.stringArray(forKey: Keys.claudeProfileDirectories) ?? []
        claudeProfileDirectories = directories
        claudeProfileCustomizations = Self.loadCustomizations(from: defaults)
        claudeProfiles = profileDiscovery(directories.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        })
        displayProviderID = ProviderID(
            rawValue: defaults.string(forKey: Keys.displayProvider) ?? ProviderID.codex.rawValue
        )
        reassignDisplayProviderIfDisabled()
    }

    var enabledDisplayProviders: [DisplayProvider] {
        var providers: [DisplayProvider] = []
        if codexEnabled {
            providers.append(.codex)
        }
        if claudeEnabled {
            providers.append(contentsOf: claudeProfiles.map {
                DisplayProvider.claude($0, customization: customization(for: $0.slug))
            })
        }
        return providers
    }

    func customization(for slug: String) -> ClaudeProfileCustomization {
        claudeProfileCustomizations[slug] ?? ClaudeProfileCustomization()
    }

    func setCustomization(_ customization: ClaudeProfileCustomization, for slug: String) {
        if customization.isEmpty {
            claudeProfileCustomizations.removeValue(forKey: slug)
        } else {
            claudeProfileCustomizations[slug] = customization
        }
        persistCustomizations()
    }

    func addClaudeProfileDirectory(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !claudeProfileDirectories.contains(path) else { return }
        claudeProfileDirectories.append(path)
        defaults.set(claudeProfileDirectories, forKey: Keys.claudeProfileDirectories)
        refreshClaudeProfiles()
    }

    func removeClaudeProfileDirectory(_ profile: ClaudeProfile) {
        let path = profile.configDirectory.standardizedFileURL.path
        claudeProfileDirectories.removeAll { $0 == path }
        defaults.set(claudeProfileDirectories, forKey: Keys.claudeProfileDirectories)
        refreshClaudeProfiles()
    }

    var currentDisplayProvider: DisplayProvider? {
        enabledDisplayProviders.first { $0.providerID == displayProviderID }
    }

    func refreshClaudeProfiles() {
        let discovered = profileDiscovery(claudeProfileDirectories.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        })
        guard discovered != claudeProfiles else { return }
        claudeProfiles = discovered
        reassignDisplayProviderIfDisabled()
    }

    func resetCodexSessionsPath() {
        codexSessionsPath = CodexDataLocation.defaultSessionsDirectory().path
    }

    var expandedCodexSessionsURL: URL {
        let expanded = NSString(string: codexSessionsPath).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private func reassignDisplayProviderIfDisabled() {
        let enabled = enabledDisplayProviders
        guard !enabled.contains(where: { $0.providerID == displayProviderID }),
              let replacement = enabled.first
        else { return }
        displayProviderID = replacement.providerID
    }

    private func persistCustomizations() {
        guard let data = try? JSONEncoder().encode(claudeProfileCustomizations) else { return }
        defaults.set(data, forKey: Keys.claudeProfileCustomizations)
    }

    private static func loadCustomizations(
        from defaults: UserDefaults
    ) -> [String: ClaudeProfileCustomization] {
        guard let data = defaults.data(forKey: Keys.claudeProfileCustomizations),
              let decoded = try? JSONDecoder().decode(
                  [String: ClaudeProfileCustomization].self,
                  from: data
              )
        else { return [:] }
        return decoded
    }

    private static func validated(
        _ value: TimeInterval,
        options: [TimeInterval],
        fallback: TimeInterval
    ) -> TimeInterval {
        options.contains(value) ? value : fallback
    }

    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let staleThreshold = "staleThreshold"
        static let codexSessionsPath = "codexSessionsPath"
        static let codexEnabled = "codexEnabled"
        static let claudeEnabled = "claudeEnabled"
        static let displayProvider = "displayProvider"
        static let claudeProfileDirectories = "claudeProfileDirectories"
        static let claudeProfileCustomizations = "claudeProfileCustomizations"
    }
}
