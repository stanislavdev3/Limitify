import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: LimitifyUsageStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject var claudeInstaller: ClaudeStatusLineInstaller

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Automatic refresh", selection: $settings.refreshInterval) {
                    ForEach(AppSettings.refreshIntervalOptions, id: \.self) { interval in
                        Text(durationLabel(interval)).tag(interval)
                    }
                }

                Picker("Mark data stale after", selection: $settings.staleThreshold) {
                    ForEach(AppSettings.staleThresholdOptions, id: \.self) { interval in
                        Text(durationLabel(interval)).tag(interval)
                    }
                }
            }

            Section("Codex") {
                Toggle("Enable Codex", isOn: $settings.codexEnabled)

                TextField("Sessions directory", text: $settings.codexSessionsPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!settings.codexEnabled)
                    .onSubmit { store.settingsDidChange() }

                HStack {
                    Button("Choose…") { chooseSessionsDirectory() }
                        .disabled(!settings.codexEnabled)
                    Button("Use Default") {
                        settings.resetCodexSessionsPath()
                        store.settingsDidChange()
                    }
                    .disabled(!settings.codexEnabled)
                    Spacer()
                }

                Text("Limitify reads only rate-limit events from this sessions directory. It never reads auth.json.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Claude") {
                Toggle("Enable Claude", isOn: $settings.claudeEnabled)

                HStack {
                    Text(claudeConnectionText)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if claudeInstaller.status == .connected {
                        Button("Disconnect") {
                            claudeInstaller.disconnect()
                            store.refresh()
                        }
                    } else {
                        Button("Connect Claude Code") {
                            claudeInstaller.connect()
                            store.refresh()
                        }
                        .disabled(claudeInstaller.status == .notInstalled || !settings.claudeEnabled)
                    }
                }

                Text("Claude Code sends only its 5-hour and weekly rate-limit fields to a local Limitify cache. Existing Claude status-line output is preserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))

                if launchAtLogin.requiresApproval {
                    Text("Allow Limitify in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let error = launchAtLogin.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 500, height: 560)
        .onChange(of: settings.codexEnabled) { _, _ in store.settingsDidChange() }
        .onChange(of: settings.claudeEnabled) { _, _ in store.settingsDidChange() }
        .onChange(of: settings.refreshInterval) { _, _ in store.settingsDidChange() }
        .onAppear {
            launchAtLogin.refreshStatus()
            claudeInstaller.refreshStatus()
        }
    }

    private func chooseSessionsDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Codex Sessions Directory"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.expandedCodexSessionsURL

        if panel.runModal() == .OK, let url = panel.url {
            settings.codexSessionsPath = url.path
            store.settingsDidChange()
        }
    }

    private func durationLabel(_ interval: TimeInterval) -> String {
        switch interval {
        case 30: return "30 seconds"
        case 60: return "1 minute"
        case 120: return "2 minutes"
        case 300: return "5 minutes"
        case 600: return "10 minutes"
        case 1_800: return "30 minutes"
        case 3_600: return "1 hour"
        default: return "\(Int(interval)) seconds"
        }
    }

    private var claudeConnectionText: String {
        switch claudeInstaller.status {
        case .notInstalled: "Claude Code is not installed"
        case .ready: "Ready to connect"
        case .connected: "Connected"
        case let .failed(message): "Connection failed: \(message)"
        }
    }
}
