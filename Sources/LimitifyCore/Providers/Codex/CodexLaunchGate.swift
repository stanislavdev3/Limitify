import Darwin
import Foundation

/// Guards against launching a codex binary that Gatekeeper would block.
///
/// Launching a quarantined, not-yet-approved executable from a background app
/// makes macOS show a "Malware Blocked" alert and move the binary to the
/// Trash. Homebrew casks keep the quarantine attribute on downloaded
/// binaries, so a codex installation that was never run from Terminal is
/// destroyed the first time Limitify spawns it.
public enum CodexLaunchGate {
    public static func isSafeToLaunch(
        _ executableURL: URL,
        assess: (URL) -> Bool = gatekeeperAccepts
    ) -> Bool {
        guard hasQuarantineAttribute(executableURL) else { return true }
        return assess(executableURL)
    }

    /// Follows symlinks, so a quarantined cask binary behind
    /// `/opt/homebrew/bin/codex` is detected through the link.
    static func hasQuarantineAttribute(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }

    /// The quarantine attribute survives Gatekeeper approval with different
    /// flags, so a real assessment separates approved binaries from ones that
    /// would be blocked on launch.
    public static func gatekeeperAccepts(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        process.arguments = ["--assess", "--type", "execute", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
