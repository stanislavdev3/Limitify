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
    public let id: ProviderID = .codex

    private let executableURL: URL
    private let responseTimeout: TimeInterval

    public init(executableURL: URL, responseTimeout: TimeInterval = 8) {
        self.executableURL = executableURL
        self.responseTimeout = max(0.1, responseTimeout)
    }

    public func fetchUsage() async throws -> ServiceUsage {
        let executableURL = executableURL
        let responseTimeout = responseTimeout
        return try await Task.detached(priority: .utility) {
            try Self.loadUsage(executableURL: executableURL, responseTimeout: responseTimeout)
        }.value
    }

    private static func loadUsage(
        executableURL: URL,
        responseTimeout: TimeInterval
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
            observedAt: observedAt
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
