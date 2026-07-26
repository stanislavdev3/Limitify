import AppKit
import LimitifyCore
import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: LimitifyUsageStore

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
            Picker("Menu bar service", selection: $settings.displayProvider) {
                ForEach(DisplayProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel("Service shown in the menu bar")
            if let plan = store.usage?.accountLabel {
                Text(planLabel(plan))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.selectedProviderEnabled {
            ContentUnavailableView(
                "\(settings.displayProvider.displayName) is disabled",
                systemImage: "pause.circle",
                description: Text("Enable \(settings.displayProvider.displayName) in Settings to show usage limits.")
            )
        } else if let usage = store.usage {
            VStack(alignment: .leading, spacing: 18) {
                if store.isStale {
                    Label("Showing stale data", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Warning: showing stale \(settings.displayProvider.displayName) usage data")
                }

                ForEach(usage.limits, id: \.id) { limit in
                    LimitRow(limit: limit)
                }

                if let failure = store.state.failure {
                    Label(failureMessage(failure), systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if store.isRefreshing {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading \(settings.displayProvider.displayName) usage…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
        } else {
            ContentUnavailableView(
                errorTitle(store.state.failure),
                systemImage: errorIcon(store.state.failure),
                description: Text(failureMessage(store.state.failure))
            )
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
                .disabled(store.isRefreshing || !store.selectedProviderEnabled)
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Refresh \(settings.displayProvider.displayName) usage")
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
        guard let date = store.state.lastSuccessfulRefreshAt else { return "Not updated yet" }
        return "Updated \(date.formatted(.relative(presentation: .named)))"
    }

    private func planLabel(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func errorTitle(_ failure: UsageProviderFailure?) -> String {
        let provider = settings.displayProvider.displayName
        switch failure {
        case .providerNotInstalled:
            return "\(provider) is not installed"
        case .dataDirectoryMissing:
            return "\(provider) data not found"
        case .noUsageEvent:
            return "No usage data yet"
        case .accessDenied:
            return "Access denied"
        case .malformedData:
            return "\(provider) data is incomplete"
        case .unsupportedData:
            return "Unsupported \(provider) data"
        default:
            return "Usage unavailable"
        }
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

    private func failureMessage(_ failure: UsageProviderFailure?) -> String {
        if settings.displayProvider == .claude {
            switch failure {
            case .providerNotInstalled:
                return "Install Claude Code, then connect it in Settings."
            case .noUsageEvent:
                return "Connect Claude Code in Settings and send one message to update its limits."
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
                return "Connect Claude Code in Settings to collect local usage limits."
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
