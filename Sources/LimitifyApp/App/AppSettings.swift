import Combine
import Foundation
import LimitifyCore

enum DisplayProvider: String, CaseIterable, Identifiable {
    case codex
    case claude

    var id: String { rawValue }
    var providerID: ProviderID { self == .codex ? .codex : .claude }
    var displayName: String { self == .codex ? "Codex" : "Claude" }
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
        didSet { defaults.set(codexEnabled, forKey: Keys.codexEnabled) }
    }

    @Published var claudeEnabled: Bool {
        didSet { defaults.set(claudeEnabled, forKey: Keys.claudeEnabled) }
    }

    @Published var displayProvider: DisplayProvider {
        didSet { defaults.set(displayProvider.rawValue, forKey: Keys.displayProvider) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.refreshInterval: 60.0,
            Keys.staleThreshold: 600.0,
            Keys.codexSessionsPath: CodexDataLocation.defaultSessionsDirectory().path,
            Keys.codexEnabled: true,
            Keys.claudeEnabled: true,
            Keys.displayProvider: DisplayProvider.codex.rawValue,
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
        displayProvider = DisplayProvider(
            rawValue: defaults.string(forKey: Keys.displayProvider) ?? ""
        ) ?? .codex
    }

    func resetCodexSessionsPath() {
        codexSessionsPath = CodexDataLocation.defaultSessionsDirectory().path
    }

    var expandedCodexSessionsURL: URL {
        let expanded = NSString(string: codexSessionsPath).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
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
    }
}
