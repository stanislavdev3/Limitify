import Foundation

enum CodexAppServerResponseDecoder {
    static func decodeUsage(from data: Data, observedAt: Date) throws -> ServiceUsage {
        let envelope: RateLimitsResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(RateLimitsResponseEnvelope.self, from: data)
        } catch {
            throw CodexAppServerError.malformedResponse
        }

        if let error = envelope.error {
            throw CodexAppServerError.rpcError(code: error.code)
        }

        guard let result = envelope.result else {
            throw CodexAppServerError.malformedResponse
        }

        let buckets: [(String, AppServerRateLimitSnapshot)]
        if let byID = result.rateLimitsByLimitID, !byID.isEmpty {
            buckets = byID.sorted { $0.key < $1.key }
        } else {
            let fallbackID = normalized(result.rateLimits.limitID) ?? ProviderID.codex.rawValue
            buckets = [(fallbackID, result.rateLimits)]
        }

        var limits: [UsageLimit] = []
        var accountLabel: String?

        for (dictionaryID, snapshot) in buckets {
            let bucketID = normalized(snapshot.limitID) ?? dictionaryID
            accountLabel = accountLabel ?? normalized(snapshot.planType)

            if let primary = snapshot.primary {
                limits.append(try map(window: primary, role: "primary", bucketID: bucketID))
            }
            if let secondary = snapshot.secondary {
                limits.append(try map(window: secondary, role: "secondary", bucketID: bucketID))
            }
        }

        guard !limits.isEmpty else {
            throw CodexAppServerError.noUsageWindows
        }

        return ServiceUsage(
            providerID: .codex,
            displayName: "Codex",
            accountLabel: accountLabel,
            limits: limits,
            observedAt: observedAt,
            source: UsageSource(kind: .appServer, freshness: .live)
        )
    }

    private static func map(
        window: AppServerRateLimitWindow,
        role: String,
        bucketID: String
    ) throws -> UsageLimit {
        guard window.usedPercent.isFinite, (0 ... 100).contains(window.usedPercent) else {
            throw CodexAppServerError.invalidUsageWindow
        }

        let minutes = window.windowDurationMinutes.flatMap { $0 > 0 ? $0 : nil }
        let resetAt = window.resetsAt.flatMap { $0 >= 0 ? Date(timeIntervalSince1970: $0) : nil }

        return try UsageLimit(
            id: "\(bucketID).\(role)",
            displayName: displayName(minutes: minutes, role: role),
            usedFraction: window.usedPercent / 100,
            windowDuration: minutes.map { TimeInterval($0) * 60 },
            resetAt: resetAt
        )
    }

    private static func displayName(minutes: Int?, role: String) -> String {
        switch minutes {
        case 300:
            return "5-hour limit"
        case 10_080:
            return "Weekly limit"
        case let minutes?:
            return "\(minutes)-minute limit"
        case nil:
            return role == "primary" ? "Primary limit" : "Secondary limit"
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

private struct RateLimitsResponseEnvelope: Decodable {
    let result: AppServerRateLimitsResult?
    let error: AppServerRPCError?
}

private struct AppServerRPCError: Decodable {
    let code: Int
}

private struct AppServerRateLimitsResult: Decodable {
    let rateLimits: AppServerRateLimitSnapshot
    let rateLimitsByLimitID: [String: AppServerRateLimitSnapshot]?

    private enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitID = "rateLimitsByLimitId"
    }
}

private struct AppServerRateLimitSnapshot: Decodable {
    let limitID: String?
    let primary: AppServerRateLimitWindow?
    let secondary: AppServerRateLimitWindow?
    let planType: String?

    private enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case primary
        case secondary
        case planType
    }
}

private struct AppServerRateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMinutes: Int?
    let resetsAt: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case usedPercent
        case windowDurationMinutes = "windowDurationMins"
        case resetsAt
    }
}
