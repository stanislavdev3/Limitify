import Foundation

public enum ClaudeUsageSourceError: Error, Equatable, Sendable {
    case providerNotInstalled
    case noUsageEvent
    case accessDenied
    case malformedData
}

public struct ClaudeUsageProvider: UsageProvider {
    public let id: ProviderID = .claude

    private let cacheFile: URL
    private let executableURL: URL?

    public init(cacheFile: URL, executableURL: URL? = ClaudeExecutableLocator.locate()) {
        self.cacheFile = cacheFile
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

        guard let payload = try? JSONDecoder().decode(CachePayload.self, from: data) else {
            throw ClaudeUsageSourceError.malformedData
        }

        var limits: [UsageLimit] = []
        if let window = payload.fiveHour {
            limits.append(try makeLimit(
                id: "claude.five-hour",
                displayName: "5-hour limit",
                duration: 5 * 60 * 60,
                window: window
            ))
        }
        if let window = payload.sevenDay {
            limits.append(try makeLimit(
                id: "claude.seven-day",
                displayName: "Weekly limit",
                duration: 7 * 24 * 60 * 60,
                window: window
            ))
        }
        guard !limits.isEmpty else {
            throw ClaudeUsageSourceError.noUsageEvent
        }

        let values = try cacheFile.resourceValues(forKeys: [.contentModificationDateKey])
        return ServiceUsage(
            providerID: .claude,
            displayName: "Claude",
            accountLabel: nil,
            limits: limits,
            observedAt: values.contentModificationDate ?? Date(),
            source: UsageSource(kind: .statusLine, freshness: .observedSnapshot)
        )
    }

    private func makeLimit(
        id: String,
        displayName: String,
        duration: TimeInterval,
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
}

private struct CachePayload: Decodable {
    let fiveHour: Window?
    let sevenDay: Window?

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct Window: Decodable {
    let usedPercentage: Double
    let resetsAt: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}
