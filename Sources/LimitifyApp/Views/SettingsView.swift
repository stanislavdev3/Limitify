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

                ForEach(settings.codexProfiles) { profile in
                    codexProfileRow(profile)
                }

                HStack {
                    Button("Add Account Directory…") { chooseCodexDirectory() }
                        .disabled(!settings.codexEnabled)
                    Spacer()
                }

                Text("Limitify reads only rate-limit events from each account's sessions directory. It never reads auth.json. Limitify finds ~/.codex-* automatically; add any other CODEX_HOME by hand.")
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
            // LSUIElement apps aren't activated automatically when a new
            // window opens, so without this the Settings window can appear
            // behind whatever app was frontmost before the menu-bar click.
            NSApplication.shared.activate(ignoringOtherApps: true)
            launchAtLogin.refreshStatus()
            settings.refreshClaudeProfiles()
            settings.refreshCodexProfiles()
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
                    Text(settings.claudeCustomization(for: profile.slug).normalizedLabel ?? profile.displayName)
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
                ProfileGroupPicker(selection: groupBinding(profile))
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
            get: { settings.claudeCustomization(for: profile.slug).label ?? "" },
            set: { value in
                var customization = settings.claudeCustomization(for: profile.slug)
                customization.label = value.isEmpty ? nil : value
                settings.setClaudeCustomization(customization, for: profile.slug)
            }
        )
    }

    private func tintBinding(_ profile: ClaudeProfile) -> Binding<ProfileTint> {
        Binding(
            get: { settings.claudeCustomization(for: profile.slug).tint },
            set: { value in
                var customization = settings.claudeCustomization(for: profile.slug)
                customization.tint = value
                settings.setClaudeCustomization(customization, for: profile.slug)
            }
        )
    }

    private func groupBinding(_ profile: ClaudeProfile) -> Binding<ProfileGroup> {
        Binding(
            get: { settings.claudeCustomization(for: profile.slug).group },
            set: { value in
                var customization = settings.claudeCustomization(for: profile.slug)
                customization.group = value
                settings.setClaudeCustomization(customization, for: profile.slug)
            }
        )
    }

    @ViewBuilder
    private func codexProfileRow(_ profile: CodexProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.codexCustomization(for: profile.slug).normalizedLabel ?? profile.displayName)
                    Text(profile.homeDirectory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if profile.isManual {
                    Button("Remove") {
                        settings.removeCodexProfileDirectory(profile)
                        store.settingsDidChange()
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("", text: codexLabelBinding(profile), prompt: Text("Custom label"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .labelsHidden()
                    .frame(maxWidth: 180)
                    .onSubmit { store.settingsDidChange() }
                ProfileTintPicker(selection: codexTintBinding(profile))
                ProfileGroupPicker(selection: codexGroupBinding(profile))
                Spacer()
            }
        }
    }

    private func codexLabelBinding(_ profile: CodexProfile) -> Binding<String> {
        Binding(
            get: { settings.codexCustomization(for: profile.slug).label ?? "" },
            set: { value in
                var customization = settings.codexCustomization(for: profile.slug)
                customization.label = value.isEmpty ? nil : value
                settings.setCodexCustomization(customization, for: profile.slug)
            }
        )
    }

    private func codexTintBinding(_ profile: CodexProfile) -> Binding<ProfileTint> {
        Binding(
            get: { settings.codexCustomization(for: profile.slug).tint },
            set: { value in
                var customization = settings.codexCustomization(for: profile.slug)
                customization.tint = value
                settings.setCodexCustomization(customization, for: profile.slug)
            }
        )
    }

    private func codexGroupBinding(_ profile: CodexProfile) -> Binding<ProfileGroup> {
        Binding(
            get: { settings.codexCustomization(for: profile.slug).group },
            set: { value in
                var customization = settings.codexCustomization(for: profile.slug)
                customization.group = value
                settings.setCodexCustomization(customization, for: profile.slug)
            }
        )
    }

    private func chooseCodexDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Codex CODEX_HOME Directory"
        panel.prompt = "Add"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        if panel.runModal() == .OK, let url = panel.url {
            settings.addCodexProfileDirectory(url)
            store.settingsDidChange()
        }
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
