import Foundation

public enum CodexSessionSourceError: Error, Equatable, Sendable {
    case dataDirectoryMissing
    case accessDenied
    case noUsageEvent
    case malformedData
}

public struct CodexSessionJSONLSource: UsageProvider {
    public let id: ProviderID = .codex

    private let sessionsDirectory: URL
    private let candidateLimit: Int
    private let initialTailBytes: Int
    private let maximumTailBytes: Int

    public init(
        sessionsDirectory: URL,
        candidateLimit: Int = 8,
        initialTailBytes: Int = 256 * 1_024,
        maximumTailBytes: Int = 2 * 1_024 * 1_024
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.candidateLimit = max(1, candidateLimit)
        self.initialTailBytes = max(1, initialTailBytes)
        self.maximumTailBytes = max(self.initialTailBytes, maximumTailBytes)
    }

    public func fetchUsage() async throws -> ServiceUsage {
        try loadUsage()
    }

    func loadUsage() throws -> ServiceUsage {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sessionsDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw CodexSessionSourceError.dataDirectoryMissing
        }

        let candidates = try sessionCandidates(fileManager: fileManager)
        var latestEvent: CodexRateLimitEvent?
        var readFailure: Error?
        var sawMalformedData = false

        for candidate in candidates.prefix(candidateLimit) {
            do {
                let scan = try scanFile(candidate.url, fileSize: candidate.fileSize)
                sawMalformedData = sawMalformedData || scan.sawMalformedRateLimitRecord
                guard let event = scan.event else {
                    continue
                }

                if latestEvent == nil || event.observedAt > latestEvent!.observedAt {
                    latestEvent = event
                }
            } catch {
                readFailure = error
            }
        }

        guard let latestEvent else {
            if let readFailure, Self.isPermissionError(readFailure) {
                throw CodexSessionSourceError.accessDenied
            }
            if sawMalformedData {
                throw CodexSessionSourceError.malformedData
            }
            throw CodexSessionSourceError.noUsageEvent
        }

        return try map(event: latestEvent)
    }

    private func sessionCandidates(fileManager: FileManager) throws -> [SessionCandidate] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw CodexSessionSourceError.accessDenied
        }

        var candidates: [SessionCandidate] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                guard values.isRegularFile == true else { continue }
                candidates.append(SessionCandidate(
                    url: url,
                    modificationDate: values.contentModificationDate ?? .distantPast,
                    fileSize: max(0, values.fileSize ?? 0)
                ))
            } catch {
                if Self.isPermissionError(error) {
                    throw CodexSessionSourceError.accessDenied
                }
            }
        }

        return candidates.sorted {
            if $0.modificationDate == $1.modificationDate {
                return $0.url.path < $1.url.path
            }
            return $0.modificationDate > $1.modificationDate
        }
    }

    private func scanFile(_ url: URL, fileSize: Int) throws -> CodexJSONLScanResult {
        guard fileSize > 0 else {
            return CodexJSONLScanResult(event: nil, sawMalformedRateLimitRecord: false)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let endOffset = try handle.seekToEnd()
        let readableSize = min(Int(clamping: endOffset), maximumTailBytes)
        var tailSize = min(initialTailBytes, readableSize)
        var sawMalformedData = false

        while tailSize > 0 {
            let startOffset = endOffset - UInt64(tailSize)
            let readOffset = startOffset > 0 ? startOffset - 1 : 0
            let readCount = tailSize + (startOffset > 0 ? 1 : 0)
            try handle.seek(toOffset: readOffset)
            var data = try handle.read(upToCount: readCount) ?? Data()

            var discardLeadingFragment = false
            if startOffset > 0, let precedingByte = data.first {
                data.removeFirst()
                discardLeadingFragment = precedingByte != UInt8(ascii: "\n")
            }

            let scan = CodexJSONLParser.scan(
                in: data,
                discardLeadingFragment: discardLeadingFragment
            )
            sawMalformedData = sawMalformedData || scan.sawMalformedRateLimitRecord
            if let event = scan.event {
                return CodexJSONLScanResult(
                    event: event,
                    sawMalformedRateLimitRecord: sawMalformedData
                )
            }

            guard tailSize < readableSize else { break }
            tailSize = min(tailSize * 2, readableSize)
        }

        return CodexJSONLScanResult(
            event: nil,
            sawMalformedRateLimitRecord: sawMalformedData
        )
    }

    private func map(event: CodexRateLimitEvent) throws -> ServiceUsage {
        let bucketID = event.limitID.flatMap { $0.isEmpty ? nil : $0 } ?? ProviderID.codex.rawValue
        let limits = try event.windows.map { window in
            try UsageLimit(
                id: "\(bucketID).\(window.role.rawValue)",
                displayName: Self.displayName(for: window),
                usedFraction: window.usedPercent / 100,
                windowDuration: window.windowMinutes.map { TimeInterval($0) * 60 },
                resetAt: window.resetsAt
            )
        }

        return ServiceUsage(
            providerID: .codex,
            displayName: "Codex",
            accountLabel: event.planType,
            limits: limits,
            observedAt: event.observedAt,
            source: UsageSource(kind: .sessionJSONL, freshness: .observedSnapshot)
        )
    }

    private static func displayName(for window: CodexRateLimitEvent.Window) -> String {
        switch window.windowMinutes {
        case 300:
            return "5-hour limit"
        case 10_080:
            return "Weekly limit"
        case let minutes?:
            return "\(minutes)-minute limit"
        case nil:
            return window.role == .primary ? "Primary limit" : "Secondary limit"
        }
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let cocoaError = error as? CocoaError
        return cocoaError?.code == .fileReadNoPermission
    }
}

private struct SessionCandidate {
    let url: URL
    let modificationDate: Date
    let fileSize: Int
}
