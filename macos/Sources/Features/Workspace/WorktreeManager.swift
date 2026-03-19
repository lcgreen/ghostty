import Foundation
import Combine
import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
    category: "worktree-manager"
)

/// Manages git worktrees and workspace lifecycle.
/// All git operations are async and run off the main thread.
/// @Published properties are mutated on the main thread via MainActor.run.
final class WorktreeManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var workspaces: [Workspace] = []
    @Published private(set) var isCreating = false

    // MARK: - Configuration

    static let basePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ghostset/worktrees"
    }()

    private let fileManager = FileManager.default
    private let persistence: WorkspacePersistence

    /// Per-workspace command history.
    let commandHistory = WorkspaceCommandHistory()

    // MARK: - Init

    init() {
        self.persistence = WorkspacePersistence()
        self.workspaces = persistence.load()
    }

    // MARK: - Session Persistence

    /// Save a workspace's terminal session layout.
    func saveSession(_ session: WorkspaceSessionState) {
        persistence.saveSession(session)
    }

    /// Load a workspace's terminal session layout.
    func loadSession(workspaceID: UUID) -> WorkspaceSessionState? {
        persistence.loadSession(workspaceID: workspaceID)
    }

    // MARK: - Create Workspace

    /// Creates a new git worktree and returns a configured Workspace.
    func createWorkspace(
        repo: String,
        name: String,
        baseBranch: String = "main",
        agent: AgentType? = nil
    ) async throws -> Workspace {
        await MainActor.run { isCreating = true }
        defer { Task { @MainActor in self.isCreating = false } }

        let repoName = repoDirectoryName(from: repo)
        let worktreePath = "\(Self.basePath)/\(repoName)/\(name)"
        let branchName = "ghostset/\(name)"

        // Ensure base directory exists
        let parentDir = "\(Self.basePath)/\(repoName)"
        try ensureDirectory(at: parentDir)

        // Create the git worktree
        try await gitWorktreeAdd(
            repo: repo,
            path: worktreePath,
            branch: branchName,
            baseBranch: baseBranch
        )

        // Log setup command if configured (not executed automatically for security)
        let config = loadRepoConfig(repo: repo)
        if let setupCmd = config?.setupCommand {
            logger.warning("Workspace config contains setupCommand '\(setupCmd)' — skipped automatic execution")
        }

        // Build workspace model
        let workspace = Workspace(
            name: name,
            repoPath: repo,
            worktreePath: worktreePath,
            branch: branchName,
            agent: agent
        )
        let readyWorkspace = withStatus(workspace, .ready)

        await MainActor.run {
            workspaces.append(readyWorkspace)
            persistence.save(workspaces)
        }

        return readyWorkspace
    }

    // MARK: - Remove Workspace

    /// Removes a workspace: kills processes, removes worktree, optionally deletes branch.
    func removeWorkspace(_ workspace: Workspace, deleteBranch: Bool = false) async throws {
        // Log teardown command if configured (not executed automatically for security)
        let config = loadRepoConfig(repo: workspace.repoPath)
        if let teardownCmd = config?.teardownCommand {
            logger.warning("Workspace config contains teardownCommand '\(teardownCmd)' — skipped automatic execution")
        }

        // Remove the git worktree
        try await gitWorktreeRemove(repo: workspace.repoPath, path: workspace.worktreePath)

        // Optionally delete the branch
        if deleteBranch {
            try await gitBranchDelete(repo: workspace.repoPath, branch: workspace.branch)
        }

        await MainActor.run {
            workspaces.removeAll { $0.id == workspace.id }
            persistence.save(workspaces)
        }
    }

    // MARK: - Refresh

    /// Syncs workspace list with actual git worktrees on disk.
    func refresh(repo: String) async throws {
        let worktrees = try await gitWorktreeList(repo: repo)
        // Update status of each known workspace based on disk state
        let updated = workspaces.map { ws in
            if worktrees.contains(ws.worktreePath) {
                return ws.status == .creating ? withStatus(ws, .ready) : ws
            } else {
                return withStatus(ws, .error("Worktree missing from disk"))
            }
        }
        await MainActor.run {
            workspaces = updated
            persistence.save(workspaces)
        }
    }

    // MARK: - Git Operations (private)

    private func gitWorktreeAdd(
        repo: String,
        path: String,
        branch: String,
        baseBranch: String
    ) async throws {
        let result = try await shell(
            "git", "-C", repo, "worktree", "add", "-b", branch, path, baseBranch
        )
        guard result.exitCode == 0 else {
            throw WorktreeError.creationFailed(result.stderr)
        }
    }

    private func gitWorktreeRemove(repo: String, path: String) async throws {
        let result = try await shell("git", "-C", repo, "worktree", "remove", "--force", path)
        guard result.exitCode == 0 else {
            throw WorktreeError.removalFailed(result.stderr)
        }
    }

    private func gitWorktreeList(repo: String) async throws -> Set<String> {
        let result = try await shell("git", "-C", repo, "worktree", "list", "--porcelain")
        guard result.exitCode == 0 else {
            throw WorktreeError.listFailed(result.stderr)
        }
        // Parse "worktree <path>" lines
        let paths = result.stdout
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("worktree ") }
            .map { String($0.dropFirst("worktree ".count)) }
        return Set(paths)
    }

    private func gitBranchDelete(repo: String, branch: String) async throws {
        _ = try await shell("git", "-C", repo, "branch", "-d", branch)
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

    // MARK: - Helpers

    private func repoDirectoryName(from repoPath: String) -> String {
        URL(fileURLWithPath: repoPath).lastPathComponent
    }

    private func ensureDirectory(at path: String) throws {
        if !fileManager.fileExists(atPath: path) {
            try fileManager.createDirectory(
                atPath: path,
                withIntermediateDirectories: true
            )
        }
    }

    private func loadRepoConfig(repo: String) -> WorkspaceConfig? {
        let configPath = "\(repo)/.ghostset/config.json"
        guard let data = fileManager.contents(atPath: configPath) else { return nil }
        return try? JSONDecoder().decode(WorkspaceConfig.self, from: data)
    }

    /// Returns a new Workspace with the given status (immutable update).
    private func withStatus(_ workspace: Workspace, _ status: WorkspaceStatus) -> Workspace {
        var updated = workspace
        updated.status = status
        return updated
    }
}

// MARK: - Supporting Types

struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum WorktreeError: LocalizedError {
    case creationFailed(String)
    case removalFailed(String)
    case listFailed(String)
    case setupFailed(String)

    var errorDescription: String? {
        switch self {
        case .creationFailed(let msg): return "Failed to create worktree: \(msg)"
        case .removalFailed(let msg): return "Failed to remove worktree: \(msg)"
        case .listFailed(let msg): return "Failed to list worktrees: \(msg)"
        case .setupFailed(let msg): return "Workspace setup failed: \(msg)"
        }
    }
}
