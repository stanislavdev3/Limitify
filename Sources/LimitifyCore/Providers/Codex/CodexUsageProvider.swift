public struct CodexUsageProvider: UsageProvider {
    public let id: ProviderID = .codex

    private let preferred: (any UsageProvider)?
    private let fallback: any UsageProvider

    public init(preferred: (any UsageProvider)?, fallback: any UsageProvider) {
        self.preferred = preferred
        self.fallback = fallback
    }

    public func fetchUsage() async throws -> ServiceUsage {
        guard let preferred else {
            do {
                return try await fallback.fetchUsage()
            } catch CodexSessionSourceError.dataDirectoryMissing {
                throw CodexAppServerError.executableUnavailable
            }
        }

        do {
            return try await preferred.fetchUsage()
        } catch {
            return try await fallback.fetchUsage()
        }
    }
}
