import Foundation

public enum UsageProviderFailure: String, Error, Equatable, Sendable {
    case providerNotInstalled
    case dataDirectoryMissing
    case noUsageEvent
    case accessDenied
    case malformedData
    case unavailable
    case unsupportedData
    case unknown
}

public struct ProviderRefreshState: Equatable, Sendable {
    public let usage: ServiceUsage?
    public let failure: UsageProviderFailure?
    public let lastAttemptAt: Date?
    public let lastSuccessfulRefreshAt: Date?

    public init(
        usage: ServiceUsage? = nil,
        failure: UsageProviderFailure? = nil,
        lastAttemptAt: Date? = nil,
        lastSuccessfulRefreshAt: Date? = nil
    ) {
        self.usage = usage
        self.failure = failure
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
    }
}

public actor UsageRefreshCoordinator {
    private let providers: [any UsageProvider]
    private var states: [ProviderID: ProviderRefreshState]
    private var inFlightRefresh: Task<[ProviderID: ProviderRefreshState], Never>?

    public init(providers: [any UsageProvider]) {
        self.providers = providers
        states = Dictionary(uniqueKeysWithValues: providers.map {
            ($0.id, ProviderRefreshState())
        })
    }

    public func currentStates() -> [ProviderID: ProviderRefreshState] {
        states
    }

    public func refresh(at attemptDate: Date = Date()) async -> [ProviderID: ProviderRefreshState] {
        if let inFlightRefresh {
            return await inFlightRefresh.value
        }

        let providers = providers
        let previousStates = states
        let task = Task {
            await withTaskGroup(
                of: (ProviderID, Result<ServiceUsage, UsageProviderFailure>).self,
                returning: [ProviderID: ProviderRefreshState].self
            ) { group in
                for provider in providers {
                    group.addTask {
                        do {
                            return (provider.id, .success(try await provider.fetchUsage()))
                        } catch {
                            return (provider.id, .failure(Self.classify(error)))
                        }
                    }
                }

                var updated = previousStates
                for await (providerID, result) in group {
                    switch result {
                    case let .success(usage):
                        updated[providerID] = ProviderRefreshState(
                            usage: usage,
                            failure: nil,
                            lastAttemptAt: attemptDate,
                            lastSuccessfulRefreshAt: attemptDate
                        )
                    case let .failure(failure):
                        let previous = previousStates[providerID]
                        updated[providerID] = ProviderRefreshState(
                            usage: previous?.usage,
                            failure: failure,
                            lastAttemptAt: attemptDate,
                            lastSuccessfulRefreshAt: previous?.lastSuccessfulRefreshAt
                        )
                    }
                }
                return updated
            }
        }

        inFlightRefresh = task
        let refreshedStates = await task.value
        states = refreshedStates
        inFlightRefresh = nil
        return refreshedStates
    }

    private static func classify(_ error: Error) -> UsageProviderFailure {
        switch error {
        case CodexSessionSourceError.dataDirectoryMissing:
            return .dataDirectoryMissing
        case CodexSessionSourceError.noUsageEvent:
            return .noUsageEvent
        case CodexSessionSourceError.accessDenied:
            return .accessDenied
        case CodexSessionSourceError.malformedData:
            return .malformedData
        case CodexAppServerError.executableUnavailable:
            return .providerNotInstalled
        case CodexAppServerError.timeout, CodexAppServerError.connectionClosed,
             CodexAppServerError.launchFailed:
            return .unavailable
        case CodexAppServerError.malformedResponse, CodexAppServerError.invalidUsageWindow,
             CodexAppServerError.noUsageWindows, CodexAppServerError.rpcError:
            return .unsupportedData
        default:
            return .unknown
        }
    }
}
