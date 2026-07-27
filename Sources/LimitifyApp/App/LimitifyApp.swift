import AppKit
import SwiftUI

@main
struct LimitifyApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var store: LimitifyUsageStore
    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    @StateObject private var claudeHub: ClaudeInstallerHub

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: LimitifyUsageStore(settings: settings))
        let hub = ClaudeInstallerHub()
        hub.sync(with: settings.claudeProfiles)
        _claudeHub = StateObject(wrappedValue: hub)
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(
                settings: settings,
                store: store,
                claudeHub: claudeHub
            )
                .onAppear {
                    settings.refreshClaudeProfiles()
                    claudeHub.sync(with: settings.claudeProfiles)
                    store.start()
                    store.refreshIfNeeded()
                }
                .onReceive(
                    NSWorkspace.shared.notificationCenter.publisher(
                        for: NSWorkspace.didWakeNotification
                    )
                ) { _ in
                    store.refresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
                    store.refresh()
                }
        } label: {
            MenuBarUsageLabel(settings: settings, store: store)
                .task { store.start() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                settings: settings,
                store: store,
                launchAtLogin: launchAtLogin,
                claudeHub: claudeHub
            )
        }
    }
}
