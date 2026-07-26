import Foundation

public enum CodexExecutableLocator {
    public static func locate(
        configuredURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let configuredURL {
            candidates.append(configuredURL)
        }

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true).appending(path: "codex")
            })
        }

        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ])

        var seen = Set<String>()
        return candidates.first { candidate in
            guard seen.insert(candidate.standardizedFileURL.path).inserted else { return false }
            return fileManager.isExecutableFile(atPath: candidate.path)
        }
    }
}
