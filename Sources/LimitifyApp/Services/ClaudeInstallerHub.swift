import Combine
import Foundation
import LimitifyCore

/// Owns one status-line installer per Claude profile and republishes their
/// status changes, since nested ObservableObjects don't propagate on their own.
@MainActor
final class ClaudeInstallerHub: ObservableObject {
    private(set) var installers: [ProviderID: ClaudeStatusLineInstaller] = [:]
    private var subscriptions: [ProviderID: AnyCancellable] = [:]

    func sync(with profiles: [ClaudeProfile]) {
        var changed = false
        for profile in profiles where installers[profile.providerID] == nil {
            let installer = ClaudeStatusLineInstaller(profile: profile)
            installers[profile.providerID] = installer
            subscriptions[profile.providerID] = installer.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
            changed = true
        }

        let current = Set(profiles.map(\.providerID))
        for providerID in installers.keys where !current.contains(providerID) {
            installers.removeValue(forKey: providerID)
            subscriptions.removeValue(forKey: providerID)
            changed = true
        }

        if changed {
            objectWillChange.send()
        }
    }

    func installer(for providerID: ProviderID) -> ClaudeStatusLineInstaller? {
        installers[providerID]
    }

    func refreshStatuses() {
        installers.values.forEach { $0.refreshStatus() }
    }
}
