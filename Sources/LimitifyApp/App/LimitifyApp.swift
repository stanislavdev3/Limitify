import AppKit
import SwiftUI

@main
struct LimitifyApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var store: LimitifyUsageStore
    @StateObject private var launchAtLogin = LaunchAtLoginManager()

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: LimitifyUsageStore(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(settings: settings, store: store)
                .onAppear {
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
            MenuBarUsageLabel(store: store, staleThreshold: settings.staleThreshold)
                .task { store.start() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                settings: settings,
                store: store,
                launchAtLogin: launchAtLogin
            )
        }
    }
}
