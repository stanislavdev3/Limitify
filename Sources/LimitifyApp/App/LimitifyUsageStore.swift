import Combine
import Foundation
import LimitifyCore

@MainActor
final class LimitifyUsageStore: ObservableObject {
    @Published private(set) var states: [ProviderID: ProviderRefreshState] = [:]
    @Published private(set) var isRefreshing = false

    private let settings: AppSettings
    private var coordinator: UsageRefreshCoordinator?
    private var appliedConfiguration: ProviderConfiguration?
    private var automaticRefreshTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
    }

    deinit {
        automaticRefreshTask?.cancel()
    }

    func start() {
        guard automaticRefreshTask == nil else { return }
        refresh()
        automaticRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.settings.refreshInterval
                try? await Task.sleep(for: .seconds(interval))
                if !Task.isCancelled {
                    await self.refreshNow()
                }
            }
        }
    }

    func refresh() {
        Task { await refreshNow() }
    }

    func refreshIfNeeded() {
        applyCurrentSettings()
        guard settings.codexEnabled || settings.claudeEnabled else { return }
        guard let lastAttempt = state.lastAttemptAt else {
            refresh()
            return
        }
        if Date().timeIntervalSince(lastAttempt) >= settings.refreshInterval {
            refresh()
        }
    }

    func settingsDidChange() {
        let changed = applyCurrentSettings()
        if changed {
            refresh()
        }
    }

    var usage: ServiceUsage? {
        state.usage
    }

    var state: ProviderRefreshState {
        state(for: settings.displayProviderID)
    }

    func state(for providerID: ProviderID) -> ProviderRefreshState {
        states[providerID] ?? ProviderRefreshState()
    }

    func usage(for provider: DisplayProvider) -> ServiceUsage? {
        state(for: provider.providerID).usage
    }

    func isStale(_ provider: DisplayProvider) -> Bool {
        guard let usage = usage(for: provider) else { return false }
        return UsagePolicy.isStale(usage, threshold: settings.staleThreshold)
    }

    var isStale: Bool {
        guard let usage else { return false }
        return UsagePolicy.isStale(usage, threshold: settings.staleThreshold)
    }

    var constrainedLimit: UsageLimit? {
        usage.flatMap(UsagePolicy.mostConstrainedLimit)
    }

    private func refreshNow() async {
        guard !isRefreshing else { return }
        applyCurrentSettings()
        guard settings.codexEnabled || settings.claudeEnabled, let coordinator else {
            states = [:]
            return
        }

        isRefreshing = true
        states = await coordinator.refresh()
        isRefreshing = false
    }

    @discardableResult
    private func applyCurrentSettings() -> Bool {
        let configuration = ProviderConfiguration(
            codexEnabled: settings.codexEnabled,
            codexProfiles: settings.codexProfiles,
            codexCustomizations: settings.codexProfileCustomizations,
            claudeEnabled: settings.claudeEnabled,
            claudeProfiles: settings.claudeProfiles,
            claudeCustomizations: settings.claudeProfileCustomizations
        )
        guard configuration != appliedConfiguration else { return false }

        appliedConfiguration = configuration
        guard configuration.codexEnabled || configuration.claudeEnabled else {
            coordinator = nil
            states = [:]
            return true
        }

        var providers: [any UsageProvider] = []
        if configuration.codexEnabled {
            providers.append(contentsOf: configuration.codexProfiles.map { profile in
                codexProvider(for: profile, configuration: configuration)
            })
        }
        if configuration.claudeEnabled {
            providers.append(contentsOf: configuration.claudeProfiles.map { profile in
                ClaudeUsageProvider(
                    cacheFile: ClaudeDataLocation.cacheFile(forProfileSlug: profile.slug),
                    providerID: profile.providerID,
                    displayName: configuration.claudeCustomizations[profile.slug]?.normalizedLabel
                        ?? profile.displayName,
                    accountLabel: profile.accountLabel
                )
            })
        }
        coordinator = UsageRefreshCoordinator(providers: providers)
        return true
    }

    /// Every profile, default included, is pinned to its own `CODEX_HOME`
    /// directory — symmetric with how Claude profiles work, and harmless
    /// for the default profile since that's the same value it would
    /// otherwise inherit from the ambient environment.
    private func codexProvider(
        for profile: CodexProfile,
        configuration: ProviderConfiguration
    ) -> CodexUsageProvider {
        let displayName = configuration.codexCustomizations[profile.slug]?.normalizedLabel
            ?? profile.displayName

        let fallback = CodexSessionJSONLSource(
            sessionsDirectory: profile.sessionsDirectory,
            providerID: profile.providerID,
            displayName: displayName
        )
        let preferred = CodexExecutableLocator.locate().map {
            CodexAppServerSource(
                executableURL: $0,
                providerID: profile.providerID,
                displayName: displayName,
                codexHomeOverride: profile.homeDirectory
            ) as any UsageProvider
        }
        return CodexUsageProvider(preferred: preferred, fallback: fallback, providerID: profile.providerID)
    }
}

private struct ProviderConfiguration: Equatable {
    let codexEnabled: Bool
    let codexProfiles: [CodexProfile]
    let codexCustomizations: [String: ProfileCustomization]
    let claudeEnabled: Bool
    let claudeProfiles: [ClaudeProfile]
    let claudeCustomizations: [String: ProfileCustomization]
}
