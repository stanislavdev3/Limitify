import LimitifyCore
import SwiftUI

struct MenuBarUsageLabel: View {
    @ObservedObject var store: LimitifyUsageStore
    let staleThreshold: TimeInterval

    var body: some View {
        if let limit = store.constrainedLimit {
            HStack(spacing: 5) {
                CompactUsageBar(fraction: limit.remainingFraction)
                Text("\(percentage(limit.remainingFraction))%")
                    .monospacedDigit()
                if store.isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .imageScale(.small)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Codex \(percentage(limit.remainingFraction)) percent remaining\(store.isStale ? ", data stale" : "")"
            )
        } else if store.isRefreshing {
            Image(systemName: "arrow.triangle.2.circlepath")
                .accessibilityLabel("Refreshing Codex usage")
        } else {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                Text("—")
            }
            .accessibilityLabel("Codex usage unavailable")
        }
    }

    private func percentage(_ fraction: Double) -> Int {
        Int((fraction * 100).rounded())
    }
}

private struct CompactUsageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().opacity(0.25)
                Capsule()
                    .frame(width: geometry.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(width: 32, height: 5)
        .accessibilityHidden(true)
    }
}
