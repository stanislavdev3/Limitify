public struct CodexUsageProvider: UsageProvider {
    public let id: ProviderID

    private let preferred: (any UsageProvider)?
    private let fallback: any UsageProvider

    public init(
        preferred: (any UsageProvider)?,
        fallback: any UsageProvider,
        providerID: ProviderID = .codex
    ) {
        self.preferred = preferred
        self.fallback = fallback
        id = providerID
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
