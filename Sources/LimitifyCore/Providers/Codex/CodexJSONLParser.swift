import Foundation

struct CodexRateLimitEvent: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        enum Role: String, Equatable, Sendable {
            case primary
            case secondary
        }

        let role: Role
        let usedPercent: Double
        let windowMinutes: Int?
        let resetsAt: Date?
    }

    let observedAt: Date
    let limitID: String?
    let limitName: String?
    let planType: String?
    let windows: [Window]
}

enum CodexJSONLParser {
    static func newestEvent(in data: Data, discardLeadingFragment: Bool = false) -> CodexRateLimitEvent? {
        scan(in: data, discardLeadingFragment: discardLeadingFragment).event
    }

    static func scan(in data: Data, discardLeadingFragment: Bool = false) -> CodexJSONLScanResult {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if discardLeadingFragment, !lines.isEmpty {
            lines.removeFirst()
        }

        var sawMalformedRateLimitRecord = false
        for line in lines.reversed() {
            let lineData = Data(line)
            if let event = parseLine(lineData) {
                return CodexJSONLScanResult(
                    event: event,
                    sawMalformedRateLimitRecord: sawMalformedRateLimitRecord
                )
            }
            if lineData.range(of: Data(#""rate_limits""#.utf8)) != nil {
                sawMalformedRateLimitRecord = true
            }
        }

        return CodexJSONLScanResult(
            event: nil,
            sawMalformedRateLimitRecord: sawMalformedRateLimitRecord
        )
    }

    static func parseLine(_ data: Data) -> CodexRateLimitEvent? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.type == "event_msg",
              envelope.payload.type == "token_count",
              let rateLimits = envelope.payload.rateLimits,
              let primary = rateLimits.primary,
              let observedAt = parseISO8601(envelope.timestamp),
              let primaryWindow = makeWindow(from: primary, role: .primary)
        else {
            return nil
        }

        var windows = [primaryWindow]
        if let secondary = rateLimits.secondary {
            guard let secondaryWindow = makeWindow(from: secondary, role: .secondary) else {
                return nil
            }
            windows.append(secondaryWindow)
        }

        return CodexRateLimitEvent(
            observedAt: observedAt,
            limitID: rateLimits.limitID,
            limitName: rateLimits.limitName,
            planType: rateLimits.planType,
            windows: windows
        )
    }

    private static func makeWindow(
        from window: WindowDTO,
        role: CodexRateLimitEvent.Window.Role
    ) -> CodexRateLimitEvent.Window? {
        guard window.usedPercent.isFinite, (0 ... 100).contains(window.usedPercent) else {
            return nil
        }

        let duration = window.windowMinutes.flatMap { $0 > 0 ? $0 : nil }
        let resetAt = window.resetsAt.flatMap { $0 >= 0 ? Date(timeIntervalSince1970: $0) : nil }

        return CodexRateLimitEvent.Window(
            role: role,
            usedPercent: window.usedPercent,
            windowMinutes: duration,
            resetsAt: resetAt
        )
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct CodexJSONLScanResult {
    let event: CodexRateLimitEvent?
    let sawMalformedRateLimitRecord: Bool
}

private struct Envelope: Decodable {
    let timestamp: String
    let type: String
    let payload: PayloadDTO
}

private struct PayloadDTO: Decodable {
    let type: String
    let rateLimits: RateLimitsDTO?

    private enum CodingKeys: String, CodingKey {
        case type
        case rateLimits = "rate_limits"
    }
}

private struct RateLimitsDTO: Decodable {
    let limitID: String?
    let limitName: String?
    let primary: WindowDTO?
    let secondary: WindowDTO?
    let planType: String?

    private enum CodingKeys: String, CodingKey {
        case limitID = "limit_id"
        case limitName = "limit_name"
        case primary
        case secondary
        case planType = "plan_type"
    }
}

private struct WindowDTO: Decodable {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}
