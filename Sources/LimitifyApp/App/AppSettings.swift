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

/// Which cross-provider bucket a card's popover row sits under. Grouping is
/// account-level, not provider-level: a "Work" Claude account and a "Work"
/// Codex account land in the same section.
enum ProfileGroup: String, CaseIterable, Codable {
    case none
    case work
    case personal

    var displayName: String {
        switch self {
        case .none: "No group"
        case .work: "Work"
        case .personal: "Personal"
        }
    }
}

/// Shared by Claude and Codex profiles alike — both need the same knobs to
/// tell same-provider accounts apart, and neither carries anything
/// provider-specific.
struct ProfileCustomization: Codable, Equatable {
    var label: String?
    var tint: ProfileTint = .none
    var group: ProfileGroup = .none

    var isEmpty: Bool { label == nil && tint == .none && group == .none }

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
    let group: ProfileGroup

    var id: String { providerID.rawValue }

    static func codex(
        _ profile: CodexProfile,
        customization: ProfileCustomization
    ) -> DisplayProvider {
        DisplayProvider(
            providerID: profile.providerID,
            kind: .codex,
            displayName: customization.normalizedLabel ?? profile.displayName,
            // Codex has no account email to show; the popover badge falls
            // back to the live usage event's plan type instead.
            accountLabel: nil,
            tint: customization.tint,
            group: customization.group
        )
    }

    static func claude(
        _ profile: ClaudeProfile,
        customization: ProfileCustomization
    ) -> DisplayProvider {
        DisplayProvider(
            providerID: profile.providerID,
            kind: .claude,
            displayName: customization.normalizedLabel ?? profile.displayName,
            accountLabel: profile.accountLabel,
            tint: customization.tint,
            group: customization.group
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
    @Published private(set) var claudeProfileCustomizations: [String: ProfileCustomization]

    @Published private(set) var codexProfiles: [CodexProfile]
    @Published private(set) var codexProfileDirectories: [String]
    @Published private(set) var codexProfileCustomizations: [String: ProfileCustomization]

    private let defaults: UserDefaults
    private let claudeProfileDiscovery: ([URL]) -> [ClaudeProfile]
    private let codexProfileDiscovery: ([URL]) -> [CodexProfile]

    init(
        defaults: UserDefaults = .standard,
        claudeProfileDiscovery: @escaping ([URL]) -> [ClaudeProfile] = {
            ClaudeProfileDiscovery.discover(additionalDirectories: $0)
        },
        codexProfileDiscovery: @escaping ([URL]) -> [CodexProfile] = {
            CodexProfileDiscovery.discover(additionalDirectories: $0)
        }
    ) {
        self.defaults = defaults
        self.claudeProfileDiscovery = claudeProfileDiscovery
        self.codexProfileDiscovery = codexProfileDiscovery
        defaults.register(defaults: [
            Keys.refreshInterval: 60.0,
            Keys.staleThreshold: 600.0,
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
        codexEnabled = defaults.bool(forKey: Keys.codexEnabled)
        claudeEnabled = defaults.bool(forKey: Keys.claudeEnabled)
        let claudeDirectories = defaults.stringArray(forKey: Keys.claudeProfileDirectories) ?? []
        claudeProfileDirectories = claudeDirectories
        claudeProfileCustomizations = Self.loadCustomizations(
            from: defaults,
            key: Keys.claudeProfileCustomizations
        )
        claudeProfiles = claudeProfileDiscovery(claudeDirectories.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        })
        let codexDirectories = defaults.stringArray(forKey: Keys.codexProfileDirectories) ?? []
        codexProfileDirectories = codexDirectories
        codexProfileCustomizations = Self.loadCustomizations(
            from: defaults,
            key: Keys.codexProfileCustomizations
        )
        codexProfiles = codexProfileDiscovery(codexDirectories.map {
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
            providers.append(contentsOf: codexProfiles.map {
                DisplayProvider.codex($0, customization: codexCustomization(for: $0.slug))
            })
        }
        if claudeEnabled {
            providers.append(contentsOf: claudeProfiles.map {
                DisplayProvider.claude($0, customization: claudeCustomization(for: $0.slug))
            })
        }
        return providers
    }

    func claudeCustomization(for slug: String) -> ProfileCustomization {
        claudeProfileCustomizations[slug] ?? ProfileCustomization()
    }

    func setClaudeCustomization(_ customization: ProfileCustomization, for slug: String) {
        if customization.isEmpty {
            claudeProfileCustomizations.removeValue(forKey: slug)
        } else {
            claudeProfileCustomizations[slug] = customization
        }
        persistCustomizations(claudeProfileCustomizations, key: Keys.claudeProfileCustomizations)
    }

    func codexCustomization(for slug: String) -> ProfileCustomization {
        codexProfileCustomizations[slug] ?? ProfileCustomization()
    }

    func setCodexCustomization(_ customization: ProfileCustomization, for slug: String) {
        if customization.isEmpty {
            codexProfileCustomizations.removeValue(forKey: slug)
        } else {
            codexProfileCustomizations[slug] = customization
        }
        persistCustomizations(codexProfileCustomizations, key: Keys.codexProfileCustomizations)
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

    func addCodexProfileDirectory(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !codexProfileDirectories.contains(path) else { return }
        codexProfileDirectories.append(path)
        defaults.set(codexProfileDirectories, forKey: Keys.codexProfileDirectories)
        refreshCodexProfiles()
    }

    func removeCodexProfileDirectory(_ profile: CodexProfile) {
        let path = profile.homeDirectory.standardizedFileURL.path
        codexProfileDirectories.removeAll { $0 == path }
        defaults.set(codexProfileDirectories, forKey: Keys.codexProfileDirectories)
        refreshCodexProfiles()
    }

    var currentDisplayProvider: DisplayProvider? {
        enabledDisplayProviders.first { $0.providerID == displayProviderID }
    }

    func refreshClaudeProfiles() {
        let discovered = claudeProfileDiscovery(claudeProfileDirectories.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        })
        guard discovered != claudeProfiles else { return }
        claudeProfiles = discovered
        reassignDisplayProviderIfDisabled()
    }

    func refreshCodexProfiles() {
        let discovered = codexProfileDiscovery(codexProfileDirectories.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        })
        guard discovered != codexProfiles else { return }
        codexProfiles = discovered
        reassignDisplayProviderIfDisabled()
    }

    private func reassignDisplayProviderIfDisabled() {
        let enabled = enabledDisplayProviders
        guard !enabled.contains(where: { $0.providerID == displayProviderID }),
              let replacement = enabled.first
        else { return }
        displayProviderID = replacement.providerID
    }

    private func persistCustomizations(_ customizations: [String: ProfileCustomization], key: String) {
        guard let data = try? JSONEncoder().encode(customizations) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadCustomizations(
        from defaults: UserDefaults,
        key: String
    ) -> [String: ProfileCustomization] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(
                  [String: ProfileCustomization].self,
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
        static let codexEnabled = "codexEnabled"
        static let claudeEnabled = "claudeEnabled"
        static let displayProvider = "displayProvider"
        static let claudeProfileDirectories = "claudeProfileDirectories"
        static let claudeProfileCustomizations = "claudeProfileCustomizations"
        static let codexProfileDirectories = "codexProfileDirectories"
        static let codexProfileCustomizations = "codexProfileCustomizations"
    }
}
