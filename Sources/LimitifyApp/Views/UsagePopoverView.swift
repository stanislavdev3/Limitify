import AppKit
import LimitifyCore
import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: LimitifyUsageStore
    @ObservedObject var claudeInstaller: ClaudeStatusLineInstaller

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 360)
    }

    private var header: some View {
        HStack {
            Text("Limitify")
                .font(.headline)
            Spacer()
            Text("Select menu bar service")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            ForEach(DisplayProvider.allCases) { provider in
                providerBlock(provider)
            }
        }
    }

    private func providerBlock(_ provider: DisplayProvider) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    settings.displayProvider = provider
                } label: {
                    Image(systemName: settings.displayProvider == provider
                          ? "circle.inset.filled"
                          : "circle")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(settings.displayProvider == provider ? Color.accentColor : .secondary)
                .disabled(!store.isEnabled(provider))
                .accessibilityLabel("Show \(provider.displayName) in the menu bar")
                .accessibilityValue(settings.displayProvider == provider ? "Selected" : "Not selected")

                ProviderStatusIcon(provider: provider)
                Text(provider.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let plan = store.usage(for: provider)?.accountLabel {
                    Text(planLabel(plan))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            providerContent(provider)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func providerContent(_ provider: DisplayProvider) -> some View {
        let state = store.state(for: provider.providerID)
        if !store.isEnabled(provider) {
            Label("Disabled in Settings", systemImage: "pause.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let usage = state.usage {
            VStack(alignment: .leading, spacing: 14) {
                if store.isStale(provider) {
                    Label("Showing stale data", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                ForEach(usage.limits, id: \.id) { limit in
                    LimitRow(limit: limit)
                }
                if let failure = state.failure {
                    Label(failureMessage(failure, provider: provider), systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if store.isRefreshing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading usage…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(failureMessage(state.failure, provider: provider), systemImage: errorIcon(state.failure))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if provider == .claude, claudeInstaller.status == .ready {
                    Button("Connect Claude Code") {
                        claudeInstaller.connect()
                        store.refresh()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack {
                Text(updatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.refresh()
                } label: {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Refresh")
                    }
                }
                .buttonStyle(.link)
                .disabled(store.isRefreshing || !(settings.codexEnabled || settings.claudeEnabled))
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Refresh all usage")
            }

            HStack {
                SettingsLink {
                    Text("Settings…")
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
            .font(.callout)
        }
    }

    private var updatedText: String {
        let dates = store.states.values.compactMap(\.lastSuccessfulRefreshAt)
        guard let date = dates.max() else { return "Not updated yet" }
        return "Updated \(date.formatted(.relative(presentation: .named)))"
    }

    private func planLabel(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func errorIcon(_ failure: UsageProviderFailure?) -> String {
        switch failure {
        case .accessDenied:
            return "lock.trianglebadge.exclamationmark"
        case .noUsageEvent:
            return "clock.badge.questionmark"
        case .malformedData:
            return "doc.badge.ellipsis"
        case .providerNotInstalled, .dataDirectoryMissing:
            return "folder.badge.questionmark"
        default:
            return "exclamationmark.triangle"
        }
    }

    private func failureMessage(
        _ failure: UsageProviderFailure?,
        provider: DisplayProvider
    ) -> String {
        if provider == .claude {
            switch failure {
            case .providerNotInstalled:
                return "Install Claude Code, then connect it in Settings."
            case .noUsageEvent:
                if claudeInstaller.status == .connected {
                    return "Restart Claude Code and send one message in an interactive session."
                }
                return "Connect Claude Code, then start a session and send one message."
            case .accessDenied:
                return "Limitify cannot read its local Claude usage cache."
            case .malformedData:
                return "Claude returned incomplete rate-limit data. Send another message, then refresh."
            case .unavailable:
                return "Claude usage could not be refreshed. The previous value is retained."
            case .unsupportedData:
                return "This Claude Code version returned an unsupported usage format."
            case .unknown:
                return "An unexpected local Claude provider error occurred."
            case .dataDirectoryMissing, nil:
                return "Connect Claude Code, then restart any open session and send one message."
            }
        }

        switch failure {
        case .providerNotInstalled:
            return "Install Codex or choose its local sessions directory in Settings."
        case .dataDirectoryMissing:
            return "Choose the Codex sessions directory in Settings."
        case .noUsageEvent:
            return "Use Codex once, then refresh Limitify."
        case .accessDenied:
            return "Limitify cannot read the configured sessions directory."
        case .malformedData:
            return "The newest usage records are malformed or partially written. Try refreshing after Codex updates them."
        case .unavailable:
            return "Codex could not be refreshed. The previous value is retained."
        case .unsupportedData:
            return "This Codex version returned an unsupported usage format."
        case .unknown:
            return "An unexpected local provider error occurred."
        case nil:
            return "Refresh to read local Codex usage."
        }
    }
}

private struct LimitRow: View {
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(limit.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(percentage)% left")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            ProgressView(value: limit.remainingFraction)
                .progressViewStyle(.linear)
                .accessibilityLabel(limit.displayName)
                .accessibilityValue("\(percentage) percent remaining")

            if let resetAt = limit.resetAt {
                Text(resetText(resetAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Reset time unavailable")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var percentage: Int {
        Int((limit.remainingFraction * 100).rounded())
    }

    private func resetText(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval > 0, interval < 86_400 {
            return "Resets \(date.formatted(.relative(presentation: .named)))"
        }
        return "Resets \(date.formatted(.dateTime.weekday(.wide).hour().minute()))"
    }
}
