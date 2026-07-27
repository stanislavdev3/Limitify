import AppKit
import LimitifyCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: LimitifyUsageStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject var claudeHub: ClaudeInstallerHub

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

                ForEach(settings.claudeProfiles) { profile in
                    claudeProfileRow(profile)
                }

                HStack {
                    Button("Add Account Directory…") { chooseClaudeDirectory() }
                        .disabled(!settings.claudeEnabled)
                    Spacer()
                }

                Text("Limitify finds ~/.claude and ~/.claude-* automatically; add any other CLAUDE_CONFIG_DIR by hand. Each account is connected separately, and Claude Code sends only its rate-limit fields to a local Limitify cache. Existing status-line output is preserved. Restart open Claude Code sessions after connecting.")
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
            settings.refreshClaudeProfiles()
            claudeHub.sync(with: settings.claudeProfiles)
            claudeHub.refreshStatuses()
        }
    }

    @ViewBuilder
    private func claudeProfileRow(_ profile: ClaudeProfile) -> some View {
        let installer = claudeHub.installer(for: profile.providerID)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.customization(for: profile.slug).normalizedLabel ?? profile.displayName)
                    Text(profile.accountLabel ?? profile.configDirectory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(claudeConnectionText(installer?.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if installer?.status == .connected {
                    Button("Disconnect") {
                        installer?.disconnect()
                        store.refresh()
                    }
                } else {
                    Button("Connect") {
                        installer?.connect()
                        store.refresh()
                    }
                    .disabled(installer == nil || installer?.status == .notInstalled || !settings.claudeEnabled)
                }
                if profile.isManual {
                    Button("Remove") {
                        settings.removeClaudeProfileDirectory(profile)
                        claudeHub.sync(with: settings.claudeProfiles)
                        store.settingsDidChange()
                    }
                }
            }

            HStack(spacing: 10) {
                // Inside a grouped Form macOS right-aligns a titled TextField's
                // value; an untitled field with a prompt keeps typing at the
                // leading edge.
                TextField("", text: labelBinding(profile), prompt: Text("Custom label"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .labelsHidden()
                    .frame(maxWidth: 180)
                    .onSubmit { store.settingsDidChange() }
                ProfileTintPicker(selection: tintBinding(profile))
                Spacer()
            }
        }
    }

    /// The binding must echo back exactly what was typed; any transformation
    /// here re-sets the field on every keystroke and breaks cursor placement.
    /// Normalization happens where the label is displayed, and the provider
    /// rebuild is deferred to onSubmit and the next popover refresh.
    private func labelBinding(_ profile: ClaudeProfile) -> Binding<String> {
        Binding(
            get: { settings.customization(for: profile.slug).label ?? "" },
            set: { value in
                var customization = settings.customization(for: profile.slug)
                customization.label = value.isEmpty ? nil : value
                settings.setCustomization(customization, for: profile.slug)
            }
        )
    }

    private func tintBinding(_ profile: ClaudeProfile) -> Binding<ProfileTint> {
        Binding(
            get: { settings.customization(for: profile.slug).tint },
            set: { value in
                var customization = settings.customization(for: profile.slug)
                customization.tint = value
                settings.setCustomization(customization, for: profile.slug)
            }
        )
    }

    private func chooseClaudeDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Claude Config Directory"
        panel.prompt = "Add"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        if panel.runModal() == .OK, let url = panel.url {
            settings.addClaudeProfileDirectory(url)
            claudeHub.sync(with: settings.claudeProfiles)
            store.settingsDidChange()
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

    private func claudeConnectionText(_ status: ClaudeStatusLineInstaller.Status?) -> String {
        switch status {
        case .notInstalled: "Claude Code is not installed"
        case .ready, nil: "Ready to connect"
        case .connected: "Connected"
        case let .failed(message): "Connection failed: \(message)"
        }
    }
}
