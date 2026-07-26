import Foundation

public enum ClaudeExecutableLocator {
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
                URL(fileURLWithPath: String($0), isDirectory: true).appending(path: "claude")
            })
        }
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
            FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".local/bin/claude"),
        ])

        var seen = Set<String>()
        return candidates.first { candidate in
            guard seen.insert(candidate.standardizedFileURL.path).inserted else { return false }
            return fileManager.isExecutableFile(atPath: candidate.path)
        }
    }
}
