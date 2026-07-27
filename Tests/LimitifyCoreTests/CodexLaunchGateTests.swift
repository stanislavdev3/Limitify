import Darwin
import Foundation
import Testing
@testable import LimitifyCore

@Suite("Codex launch gate")
struct CodexLaunchGateTests {
    @Test("Executables without a quarantine attribute launch without assessment")
    func noQuarantine() throws {
        let executable = try TemporaryExecutable()

        var assessed = false
        let safe = CodexLaunchGate.isSafeToLaunch(executable.url) { _ in
            assessed = true
            return false
        }

        #expect(safe)
        #expect(!assessed)
    }

    @Test("Quarantined executables rejected by Gatekeeper are not launched")
    func quarantinedRejected() throws {
        let executable = try TemporaryExecutable(quarantined: true)

        #expect(CodexLaunchGate.hasQuarantineAttribute(executable.url))
        #expect(!CodexLaunchGate.isSafeToLaunch(executable.url) { _ in false })
    }

    @Test("Quarantined executables approved by Gatekeeper are launched")
    func quarantinedApproved() throws {
        let executable = try TemporaryExecutable(quarantined: true)

        #expect(CodexLaunchGate.isSafeToLaunch(executable.url) { _ in true })
    }

    @Test("Quarantine is detected through a symlink")
    func quarantinedBehindSymlink() throws {
        let executable = try TemporaryExecutable(quarantined: true)
        let link = executable.url.deletingLastPathComponent().appending(path: "codex-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable.url)

        #expect(CodexLaunchGate.hasQuarantineAttribute(link))
    }
}

private final class TemporaryExecutable {
    let url: URL
    private let directory: URL

    init(quarantined: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "LimitifyLaunchGateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "fake-codex")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        if quarantined {
            let value = "0081;00000000;LimitifyTests;"
            guard setxattr(url.path, "com.apple.quarantine", value, value.utf8.count, 0, 0) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
