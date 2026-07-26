import Combine
import Foundation
import LimitifyCore

@MainActor
final class LimitifyUsageStore: ObservableObject {
    @Published private(set) var state = ProviderRefreshState()
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
        guard settings.codexEnabled else { return }
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
        guard settings.codexEnabled, let coordinator else {
            state = ProviderRefreshState()
            return
        }

        isRefreshing = true
        let states = await coordinator.refresh()
        state = states[.codex] ?? ProviderRefreshState(failure: .unknown)
        isRefreshing = false
    }

    @discardableResult
    private func applyCurrentSettings() -> Bool {
        let configuration = ProviderConfiguration(
            enabled: settings.codexEnabled,
            sessionsURL: settings.expandedCodexSessionsURL
        )
        guard configuration != appliedConfiguration else { return false }

        appliedConfiguration = configuration
        guard configuration.enabled else {
            coordinator = nil
            state = ProviderRefreshState()
            return true
        }

        let fallback = CodexSessionJSONLSource(sessionsDirectory: configuration.sessionsURL)
        let preferred = CodexExecutableLocator.locate().map {
            CodexAppServerSource(executableURL: $0) as any UsageProvider
        }
        let provider = CodexUsageProvider(preferred: preferred, fallback: fallback)
        coordinator = UsageRefreshCoordinator(providers: [provider])
        return true
    }
}

private struct ProviderConfiguration: Equatable {
    let enabled: Bool
    let sessionsURL: URL
}
