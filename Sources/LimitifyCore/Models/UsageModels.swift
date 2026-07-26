import Foundation

public struct ProviderID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension ProviderID {
    static let codex = ProviderID(rawValue: "codex")
    static let claude = ProviderID(rawValue: "claude")
}

public enum UsageSourceKind: String, Codable, Sendable {
    case appServer
    case sessionJSONL
    case statusLine
}

public enum UsageSourceFreshness: String, Codable, Sendable {
    case live
    case observedSnapshot
}

public struct UsageSource: Equatable, Codable, Sendable {
    public let kind: UsageSourceKind
    public let freshness: UsageSourceFreshness

    public init(kind: UsageSourceKind, freshness: UsageSourceFreshness) {
        self.kind = kind
        self.freshness = freshness
    }
}

public enum UsageModelError: Error, Equatable, Sendable {
    case invalidUsedFraction
}

public struct UsageLimit: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let usedFraction: Double
    public let windowDuration: TimeInterval?
    public let resetAt: Date?

    public var remainingFraction: Double {
        1 - usedFraction
    }

    public init(
        id: String,
        displayName: String,
        usedFraction: Double,
        windowDuration: TimeInterval?,
        resetAt: Date?
    ) throws {
        guard usedFraction.isFinite, (0 ... 1).contains(usedFraction) else {
            throw UsageModelError.invalidUsedFraction
        }

        self.id = id
        self.displayName = displayName
        self.usedFraction = usedFraction
        self.windowDuration = windowDuration
        self.resetAt = resetAt
    }
}

public struct ServiceUsage: Equatable, Sendable {
    public let providerID: ProviderID
    public let displayName: String
    public let accountLabel: String?
    public let limits: [UsageLimit]
    public let observedAt: Date
    public let source: UsageSource

    public init(
        providerID: ProviderID,
        displayName: String,
        accountLabel: String?,
        limits: [UsageLimit],
        observedAt: Date,
        source: UsageSource
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.accountLabel = accountLabel
        self.limits = limits
        self.observedAt = observedAt
        self.source = source
    }
}
