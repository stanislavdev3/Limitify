import Foundation

public enum ClaudeUsageSourceError: Error, Equatable, Sendable {
    case providerNotInstalled
    case noUsageEvent
    case accessDenied
    case malformedData
}

public struct ClaudeUsageProvider: UsageProvider {
    public let id: ProviderID

    private let cacheFile: URL
    private let displayName: String
    private let accountLabel: String?
    private let executableURL: URL?

    public init(
        cacheFile: URL,
        providerID: ProviderID = .claude,
        displayName: String = "Claude",
        accountLabel: String? = nil,
        executableURL: URL? = ClaudeExecutableLocator.locate()
    ) {
        self.cacheFile = cacheFile
        id = providerID
        self.displayName = displayName
        self.accountLabel = accountLabel
        self.executableURL = executableURL
    }

    public func fetchUsage() async throws -> ServiceUsage {
        try loadUsage()
    }

    func loadUsage() throws -> ServiceUsage {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: cacheFile.path) else {
            throw executableURL == nil
                ? ClaudeUsageSourceError.providerNotInstalled
                : ClaudeUsageSourceError.noUsageEvent
        }

        let data: Data
        do {
            data = try Data(contentsOf: cacheFile, options: .mappedIfSafe)
        } catch {
            if (error as? CocoaError)?.code == .fileReadNoPermission {
                throw ClaudeUsageSourceError.accessDenied
            }
            throw ClaudeUsageSourceError.malformedData
        }

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageSourceError.malformedData
        }

        var limits: [UsageLimit] = []
        for descriptor in Self.knownWindows {
            guard let raw = payload[descriptor.key], !(raw is NSNull) else { continue }
            guard let window = Self.window(from: raw) else {
                throw ClaudeUsageSourceError.malformedData
            }
            limits.append(try makeLimit(
                id: descriptor.id,
                displayName: descriptor.displayName,
                duration: descriptor.duration,
                window: window
            ))
        }

        // Future windows the status line may start reporting are shown with a
        // humanized name rather than dropped; entries that don't look like
        // windows are ignored.
        let knownKeys = Set(Self.knownWindows.map(\.key))
        for key in payload.keys.sorted() where !knownKeys.contains(key) {
            guard let raw = payload[key],
                  let window = Self.window(from: raw),
                  let limit = try? makeLimit(
                      id: "claude.\(key.replacingOccurrences(of: "_", with: "-"))",
                      displayName: Self.humanized(key),
                      duration: nil,
                      window: window
                  )
            else { continue }
            limits.append(limit)
        }

        guard !limits.isEmpty else {
            throw ClaudeUsageSourceError.noUsageEvent
        }

        let values = try cacheFile.resourceValues(forKeys: [.contentModificationDateKey])
        return ServiceUsage(
            providerID: id,
            displayName: displayName,
            accountLabel: accountLabel,
            limits: limits,
            observedAt: values.contentModificationDate ?? Date(),
            source: UsageSource(kind: .statusLine, freshness: .observedSnapshot)
        )
    }

    private func makeLimit(
        id: String,
        displayName: String,
        duration: TimeInterval?,
        window: Window
    ) throws -> UsageLimit {
        guard window.usedPercentage.isFinite,
              (0 ... 100).contains(window.usedPercentage),
              window.resetsAt >= 0
        else {
            throw ClaudeUsageSourceError.malformedData
        }
        return try UsageLimit(
            id: id,
            displayName: displayName,
            usedFraction: window.usedPercentage / 100,
            windowDuration: duration,
            resetAt: Date(timeIntervalSince1970: window.resetsAt)
        )
    }

    private struct WindowDescriptor {
        let key: String
        let id: String
        let displayName: String
        let duration: TimeInterval
    }

    private static let knownWindows: [WindowDescriptor] = [
        WindowDescriptor(
            key: "five_hour",
            id: "claude.five-hour",
            displayName: "5-hour limit",
            duration: 5 * 60 * 60
        ),
        WindowDescriptor(
            key: "seven_day",
            id: "claude.seven-day",
            displayName: "Weekly limit",
            duration: 7 * 24 * 60 * 60
        ),
        WindowDescriptor(
            key: "seven_day_sonnet",
            id: "claude.seven-day-sonnet",
            displayName: "Weekly Sonnet limit",
            duration: 7 * 24 * 60 * 60
        ),
        WindowDescriptor(
            key: "seven_day_opus",
            id: "claude.seven-day-opus",
            displayName: "Weekly Opus limit",
            duration: 7 * 24 * 60 * 60
        ),
        // Not yet reported by the status line (only five_hour and seven_day
        // are documented); named here ahead of time following the
        // seven_day_opus convention so a Fable window renders properly the
        // moment Anthropic ships it.
        WindowDescriptor(
            key: "seven_day_fable",
            id: "claude.seven-day-fable",
            displayName: "Weekly Fable limit",
            duration: 7 * 24 * 60 * 60
        ),
    ]

    private struct Window {
        let usedPercentage: Double
        let resetsAt: TimeInterval
    }

    private static func window(from raw: Any) -> Window? {
        guard let object = raw as? [String: Any],
              let usedPercentage = number(object["used_percentage"]),
              let resetsAt = number(object["resets_at"])
        else { return nil }
        return Window(usedPercentage: usedPercentage, resetsAt: resetsAt)
    }

    /// JSONSerialization bridges JSON booleans to NSNumber too; a boolean
    /// percentage must read as malformed data, not as 0 or 1.
    private static func number(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        return number.doubleValue
    }

    private static func humanized(_ key: String) -> String {
        let words = key.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
