import Foundation

public enum UsagePolicy {
    public static func isStale(
        _ usage: ServiceUsage,
        at now: Date = Date(),
        threshold: TimeInterval
    ) -> Bool {
        now.timeIntervalSince(usage.observedAt) > max(0, threshold)
    }

    public static func mostConstrainedLimit(in usage: ServiceUsage) -> UsageLimit? {
        usage.limits.min {
            if $0.remainingFraction == $1.remainingFraction {
                return $0.id < $1.id
            }
            return $0.remainingFraction < $1.remainingFraction
        }
    }
}
