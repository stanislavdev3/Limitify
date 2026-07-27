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
            codexSessionsURL: settings.expandedCodexSessionsURL,
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
            let fallback = CodexSessionJSONLSource(sessionsDirectory: configuration.codexSessionsURL)
            let preferred = CodexExecutableLocator.locate().map {
                CodexAppServerSource(executableURL: $0) as any UsageProvider
            }
            providers.append(CodexUsageProvider(preferred: preferred, fallback: fallback))
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
}

private struct ProviderConfiguration: Equatable {
    let codexEnabled: Bool
    let codexSessionsURL: URL
    let claudeEnabled: Bool
    let claudeProfiles: [ClaudeProfile]
    let claudeCustomizations: [String: ClaudeProfileCustomization]
}
