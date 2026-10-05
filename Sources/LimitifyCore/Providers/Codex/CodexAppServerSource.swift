import Foundation

public enum CodexAppServerError: Error, Equatable, Sendable {
    case executableUnavailable
    case executableQuarantined
    case launchFailed
    case timeout
    case connectionClosed
    case malformedResponse
    case rpcError(code: Int)
    case invalidUsageWindow
    case noUsageWindows
}

public struct CodexAppServerSource: UsageProvider {
    public let id: ProviderID

    private let executableURL: URL
    private let responseTimeout: TimeInterval
    private let displayName: String
    /// Set only for a non-default profile: pins the spawned `codex`
    /// process to that profile's `CODEX_HOME` so it answers for the right
    /// account. The default profile leaves this nil and inherits whatever
    /// `CODEX_HOME` Limitify itself was launched with, preserving today's
    /// single-account behavior exactly.
    private let codexHomeOverride: URL?

    public init(
        executableURL: URL,
        responseTimeout: TimeInterval = 8,
        providerID: ProviderID = .codex,
        displayName: String = "Codex",
        codexHomeOverride: URL? = nil
    ) {
        self.executableURL = executableURL
        self.responseTimeout = max(0.1, responseTimeout)
        id = providerID
        self.displayName = displayName
        self.codexHomeOverride = codexHomeOverride
    }

    public func fetchUsage() async throws -> ServiceUsage {
        let executableURL = executableURL
        let responseTimeout = responseTimeout
        let providerID = id
        let displayName = displayName
        let codexHomeOverride = codexHomeOverride
        return try await Task.detached(priority: .utility) {
            try Self.loadUsage(
                executableURL: executableURL,
                responseTimeout: responseTimeout,
                providerID: providerID,
                displayName: displayName,
                codexHomeOverride: codexHomeOverride
            )
        }.value
    }

    private static func loadUsage(
        executableURL: URL,
        responseTimeout: TimeInterval,
        providerID: ProviderID,
        displayName: String,
        codexHomeOverride: URL?
    ) throws -> ServiceUsage {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CodexAppServerError.executableUnavailable
        }
        guard CodexLaunchGate.isSafeToLaunch(executableURL) else {
            throw CodexAppServerError.executableQuarantined
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        let collector = JSONLineCollector()

        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        if let codexHomeOverride {
            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_HOME"] = codexHomeOverride.path
            process.environment = environment
        }

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                collector.finish()
            } else {
                collector.ingest(data)
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            throw CodexAppServerError.launchFailed
        }

        defer {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
        }

        try write(
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"limitify","version":"0.1.0"},"capabilities":{"experimentalApi":false}}}"#,
            to: input.fileHandleForWriting
        )
        let initializeData = try collector.waitForResponse(id: 1, timeout: responseTimeout)
        try validateResponse(initializeData)

        try write(#"{"method":"initialized"}"#, to: input.fileHandleForWriting)
        try write(
            #"{"id":2,"method":"account/rateLimits/read","params":null}"#,
            to: input.fileHandleForWriting
        )
        let rateLimitData = try collector.waitForResponse(id: 2, timeout: responseTimeout)
        let observedAt = Date()

        return try CodexAppServerResponseDecoder.decodeUsage(
            from: rateLimitData,
            observedAt: observedAt,
            providerID: providerID,
            displayName: displayName
        )
    }

    private static func write(_ line: String, to handle: FileHandle) throws {
        guard let data = "\(line)\n".data(using: .utf8) else {
            throw CodexAppServerError.connectionClosed
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw CodexAppServerError.connectionClosed
        }
    }

    private static func validateResponse(_ data: Data) throws {
        guard let probe = try? JSONDecoder().decode(RPCResponseProbe.self, from: data) else {
            throw CodexAppServerError.malformedResponse
        }
        if let error = probe.error {
            throw CodexAppServerError.rpcError(code: error.code)
        }
        guard probe.result != nil else {
            throw CodexAppServerError.malformedResponse
        }
    }
}

private struct RPCResponseProbe: Decodable {
    let result: EmptyResult?
    let error: RPCErrorProbe?
}

private struct EmptyResult: Decodable {}

private struct RPCErrorProbe: Decodable {
    let code: Int
}

private final class JSONLineCollector: @unchecked Sendable {
    private let condition = NSCondition()
    private var buffer = Data()
    private var responses: [Int: Data] = [:]
    private var reachedEOF = false

    func ingest(_ data: Data) {
        condition.lock()
        defer {
            condition.broadcast()
            condition.unlock()
        }

        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let probe = try? JSONDecoder().decode(ResponseIDProbe.self, from: line)
            else {
                continue
            }
            responses[probe.id] = line
        }
    }

    func waitForResponse(id: Int, timeout: TimeInterval) throws -> Data {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }

        while responses[id] == nil, !reachedEOF {
            guard condition.wait(until: deadline) else {
                throw CodexAppServerError.timeout
            }
        }

        guard let response = responses.removeValue(forKey: id) else {
            throw CodexAppServerError.connectionClosed
        }
        return response
    }

    func finish() {
        condition.lock()
        reachedEOF = true
        condition.broadcast()
        condition.unlock()
    }
}

private struct ResponseIDProbe: Decodable {
    let id: Int
}
