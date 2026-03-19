import SwiftUI

// MARK: - Shared Agent Color Mapping

/// Centralized agent color mapping — previously duplicated in 5+ files.
enum AgentColors {
    static func color(for agent: AgentType) -> Color {
        switch agent {
        case .claude: return .orange
        case .codex: return .green
        case .copilot: return .indigo
        case .opencode: return .teal
        case .gemini: return .blue
        case .cursor: return .purple
        case .custom: return .secondary
        }
    }
}

// MARK: - Shared Git Shell Helper

/// Synchronous git command execution — previously duplicated in 3+ files.
enum GitShell {
    /// Runs a git command synchronously and returns stdout, or nil on failure.
    static func output(_ args: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // Drop "git" prefix if present
        let gitArgs = args.first == "git" ? Array(args.dropFirst()) : args
        process.arguments = gitArgs
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Runs a git command asynchronously and returns stdout, or nil on failure.
    static func asyncOutput(_ args: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: output(args))
            }
        }
    }

    /// Parses `git diff --shortstat` output into WorkspaceChangeStats.
    static func parseShortstat(_ output: String) -> WorkspaceChangeStats {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .zero }

        var adds = 0, dels = 0, files = 0
        let parts = trimmed.components(separatedBy: ", ")
        for part in parts {
            let tokens = part.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            guard let num = Int(tokens.first ?? "") else { continue }
            if part.contains("file") { files = num }
            else if part.contains("insertion") { adds = num }
            else if part.contains("deletion") { dels = num }
        }
        return WorkspaceChangeStats(additions: adds, deletions: dels, filesChanged: files)
    }
}

// MARK: - Fuzzy Matching

/// Simple fuzzy match scoring — characters must appear in order, consecutive runs score higher.
enum FuzzyMatch {
    /// Returns a score (higher = better match), or nil if no match.
    static func score(query: String, target: String) -> Int? {
        let queryChars = Array(query.lowercased())
        let targetChars = Array(target.lowercased())
        guard !queryChars.isEmpty else { return 0 }

        var queryIdx = 0
        var score = 0
        var prevMatchIdx = -2 // Track consecutive matches

        for (targetIdx, char) in targetChars.enumerated() {
            guard queryIdx < queryChars.count else { break }
            if char == queryChars[queryIdx] {
                score += 1
                // Bonus for consecutive matches
                if targetIdx == prevMatchIdx + 1 {
                    score += 3
                }
                // Bonus for matching at start or after separator
                if targetIdx == 0 || (targetIdx > 0 && isSeparator(targetChars[targetIdx - 1])) {
                    score += 5
                }
                prevMatchIdx = targetIdx
                queryIdx += 1
            }
        }

        // All query characters must be found
        return queryIdx == queryChars.count ? score : nil
    }

    private static func isSeparator(_ c: Character) -> Bool {
        c == " " || c == "-" || c == "_" || c == "/" || c == "."
    }
}

// MARK: - Conventional Commit Prefixes

enum ConventionalCommit {
    struct Prefix {
        let label: String
        let emoji: String
        let description: String
    }

    static let prefixes: [Prefix] = [
        Prefix(label: "feat:", emoji: "✨", description: "New feature"),
        Prefix(label: "fix:", emoji: "🐛", description: "Bug fix"),
        Prefix(label: "refactor:", emoji: "♻️", description: "Refactoring"),
        Prefix(label: "docs:", emoji: "📝", description: "Documentation"),
        Prefix(label: "test:", emoji: "✅", description: "Tests"),
        Prefix(label: "chore:", emoji: "🔧", description: "Maintenance"),
        Prefix(label: "perf:", emoji: "⚡", description: "Performance"),
        Prefix(label: "ci:", emoji: "🔄", description: "CI/CD"),
    ]
}
