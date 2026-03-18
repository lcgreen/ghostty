import Foundation

/// Async git operations for workspace management.
/// Uses shell git commands (not libgit2) for simplicity and reliability.
/// All methods are isolated to an actor for thread safety.
actor GitService {

    // MARK: - File Changes

    struct FileChange: Identifiable {
        let id = UUID()
        let path: String
        let status: ChangeStatus
        let additions: Int
        let deletions: Int
    }

    enum ChangeStatus: String {
        case added = "A"
        case modified = "M"
        case deleted = "D"
        case renamed = "R"
        case untracked = "?"

        var displayLabel: String {
            switch self {
            case .added: return "Added"
            case .modified: return "Modified"
            case .deleted: return "Deleted"
            case .renamed: return "Renamed"
            case .untracked: return "Untracked"
            }
        }
    }

    // MARK: - Changed Files

    /// Returns all changed files (staged + unstaged + untracked) in a worktree.
    func changedFiles(in worktree: String) async throws -> [FileChange] {
        let result = try await shell(
            "git", "-C", worktree, "status", "--porcelain", "-uall"
        )
        guard result.exitCode == 0 else {
            throw GitError.commandFailed("git status", result.stderr)
        }

        return result.stdout
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .map { parseStatusLine($0) }
    }

    // MARK: - Diff

    struct UnifiedDiff {
        let filePath: String
        let hunks: [DiffHunk]
    }

    struct DiffHunk {
        let header: String
        let lines: [DiffLine]
    }

    struct DiffLine {
        let type: DiffLineType
        let content: String
    }

    enum DiffLineType {
        case context
        case addition
        case deletion
    }

    /// Returns the unified diff for a specific file in a worktree.
    func diff(file: String, in worktree: String) async throws -> String {
        let result = try await shell(
            "git", "-C", worktree, "diff", "--", file
        )
        // Also check staged diff
        let stagedResult = try await shell(
            "git", "-C", worktree, "diff", "--cached", "--", file
        )

        let combined = [result.stdout, stagedResult.stdout]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return combined.isEmpty ? "(no diff)" : combined
    }

    // MARK: - Diff Stats

    /// Returns summary stats (files changed, insertions, deletions).
    func diffStats(in worktree: String) async throws -> (files: Int, additions: Int, deletions: Int) {
        let result = try await shell(
            "git", "-C", worktree, "diff", "--shortstat"
        )
        return parseShortstat(result.stdout)
    }

    // MARK: - Commit

    /// Stages specified files and creates a commit.
    func commit(message: String, files: [String], in worktree: String) async throws {
        // Stage files
        for file in files {
            let addResult = try await shell("git", "-C", worktree, "add", "--", file)
            guard addResult.exitCode == 0 else {
                throw GitError.commandFailed("git add \(file)", addResult.stderr)
            }
        }

        // Commit
        let result = try await shell("git", "-C", worktree, "commit", "-m", message)
        guard result.exitCode == 0 else {
            throw GitError.commandFailed("git commit", result.stderr)
        }
    }

    // MARK: - Push

    /// Pushes the current branch to origin.
    func push(in worktree: String) async throws {
        let result = try await shell(
            "git", "-C", worktree, "push", "-u", "origin", "HEAD"
        )
        guard result.exitCode == 0 else {
            throw GitError.commandFailed("git push", result.stderr)
        }
    }

    // MARK: - Create PR

    /// Creates a pull request via gh CLI. Returns the PR URL.
    func createPR(
        title: String,
        body: String,
        in worktree: String
    ) async throws -> String {
        let result = try await shell(
            "gh", "pr", "create",
            "--title", title,
            "--body", body,
            "--repo", try repoRemote(in: worktree)
        )
        guard result.exitCode == 0 else {
            throw GitError.commandFailed("gh pr create", result.stderr)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Branch Info

    /// Returns the current branch name.
    func currentBranch(in worktree: String) async throws -> String {
        let result = try await shell(
            "git", "-C", worktree, "rev-parse", "--abbrev-ref", "HEAD"
        )
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the remote URL for the repository.
    private func repoRemote(in worktree: String) async throws -> String {
        let result = try await shell(
            "git", "-C", worktree, "remote", "get-url", "origin"
        )
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Parsing

    private func parseStatusLine(_ line: String) -> FileChange {
        let statusChar = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
        let path = String(line.dropFirst(3))

        let status: ChangeStatus
        switch statusChar {
        case "A", "AM": status = .added
        case "M", "MM": status = .modified
        case "D": status = .deleted
        case "R": status = .renamed
        case "??": status = .untracked
        default: status = .modified
        }

        return FileChange(path: path, status: status, additions: 0, deletions: 0)
    }

    private func parseShortstat(_ output: String) -> (files: Int, additions: Int, deletions: Int) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (0, 0, 0) }

        var files = 0, adds = 0, dels = 0
        let parts = trimmed.components(separatedBy: ", ")
        for part in parts {
            let tokens = part.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            guard let num = Int(tokens.first ?? "") else { continue }
            if part.contains("file") { files = num }
            else if part.contains("insertion") { adds = num }
            else if part.contains("deletion") { dels = num }
        }
        return (files, adds, dels)
    }

    // MARK: - Shell Execution

    private func shell(_ args: String...) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = args
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()

                    continuation.resume(returning: ShellResult(
                        exitCode: process.terminationStatus,
                        stdout: String(data: outData, encoding: .utf8) ?? "",
                        stderr: String(data: errData, encoding: .utf8) ?? ""
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Errors

enum GitError: LocalizedError {
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let stderr):
            return "\(cmd) failed: \(stderr)"
        }
    }
}
