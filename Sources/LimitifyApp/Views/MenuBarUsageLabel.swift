import AppKit
import LimitifyCore
import SwiftUI

struct MenuBarUsageLabel: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: LimitifyUsageStore

    private var displayName: String {
        settings.currentDisplayProvider?.displayName ?? "Usage"
    }

    var body: some View {
        if let limit = store.constrainedLimit {
            Label {
                Text(statusText(for: limit))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            } icon: {
                ProviderStatusIcon(
                    kind: settings.displayProviderID.isClaudeProvider ? .claude : .codex
                )
            }
            .labelStyle(.titleAndIcon)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(displayName) \(percentage(limit.remainingFraction)) percent remaining\(store.isStale ? ", data stale" : "")"
            )
        } else if store.isRefreshing {
            Image(systemName: "arrow.triangle.2.circlepath")
                .accessibilityLabel("Refreshing \(displayName) usage")
        } else {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                Text("—")
            }
            .accessibilityLabel("\(displayName) usage unavailable")
        }
    }

    private func percentage(_ fraction: Double) -> Int {
        Int((fraction * 100).rounded())
    }

    private func statusText(for limit: UsageLimit) -> String {
        let warning = store.isStale ? " !" : ""
        return "\(UsageBarSegments.text(for: limit.remainingFraction)) \(percentage(limit.remainingFraction))%\(warning)"
    }

}

struct OpenAIStatusIcon: View {
    static let pointSize = NSSize(width: 14, height: 14)

    static let image: NSImage? = {
        let packagedURL = Bundle.main.url(
            forResource: "OpenAIBlossom",
            withExtension: "svg"
        )
        let resourceURL = Bundle.module.url(
            forResource: "OpenAIBlossom",
            withExtension: "svg"
        )
        guard let url = packagedURL ?? resourceURL,
              let source = NSImage(contentsOf: url)
        else {
            return nil
        }

        // A menu-bar Label uses the NSImage's intrinsic size. Wrapping the SVG in
        // a fixed-size image prevents AppKit from laying out its large SVG canvas
        // and clipping the Blossom to the status item's height.
        let statusImage = NSImage(size: pointSize, flipped: false) { rect in
            source.draw(
                in: rect,
                from: NSRect(origin: .zero, size: source.size),
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        statusImage.isTemplate = true
        return statusImage
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .renderingMode(.template)
                .frame(width: 14, height: 14)
        } else {
            Text("OAI")
                .font(.system(size: 7, weight: .bold, design: .rounded))
        }
    }
}

struct ClaudeStatusIcon: View {
    static let pointSize = NSSize(width: 14, height: 14)
    static let image = ProviderIconImage.load(resource: "Claude", pointSize: pointSize)

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .renderingMode(.template)
                .frame(width: 14, height: 14)
        } else {
            Text("C")
                .font(.system(size: 8, weight: .bold, design: .rounded))
        }
    }
}

struct ProviderStatusIcon: View {
    let kind: DisplayProvider.Kind

    @ViewBuilder
    var body: some View {
        switch kind {
        case .codex: OpenAIStatusIcon()
        case .claude: ClaudeStatusIcon()
        }
    }
}

private enum ProviderIconImage {
    static func load(resource: String, pointSize: NSSize) -> NSImage? {
        let packagedURL = Bundle.main.url(forResource: resource, withExtension: "svg")
        let resourceURL = Bundle.module.url(forResource: resource, withExtension: "svg")
        guard let url = packagedURL ?? resourceURL,
              let source = NSImage(contentsOf: url)
        else { return nil }

        let image = NSImage(size: pointSize, flipped: false) { rect in
            source.draw(
                in: rect,
                from: NSRect(origin: .zero, size: source.size),
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        image.isTemplate = true
        return image
    }
}

enum UsageBarSegments {
    static let count = 5

    static func filledCount(for fraction: Double) -> Int {
        let clamped = max(0, min(1, fraction))
        return min(count, max(0, Int((clamped * Double(count)).rounded())))
    }

    static func text(for fraction: Double) -> String {
        let filled = filledCount(for: fraction)
        return String(repeating: "▰", count: filled)
            + String(repeating: "▱", count: count - filled)
    }
}
