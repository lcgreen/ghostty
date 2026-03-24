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
    @Published var tagDefinitions: [TagDefinition] = []
    @Published var templates: [WorkspaceTemplate] = []
    @Published var environmentProfiles: [EnvironmentProfile] = []
    @Published var activeProfileID: UUID?

    let notifier = WorkspaceNotifier()

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
        self.tagDefinitions = persistence.loadTagDefinitions()
        self.templates = templatePersistence.load()
        self.environmentProfiles = persistence.loadEnvironmentProfiles()
        self.activeProfileID = persistence.loadActiveProfileID()
        startAutoSave()
        detectCrashRecovery()
    }

    private let templatePersistence = TemplatePersistence()
    private var autoSaveTimer: Timer?

    /// Periodically save state every 60 seconds.
    private func startAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.saveInBackground()
        }
    }

    /// Detect unclean shutdown and log a warning.
    private func detectCrashRecovery() {
        let key = "ghostset.cleanShutdown"
        let wasClean = UserDefaults.standard.bool(forKey: key)
        if !wasClean && !workspaces.isEmpty {
            logger.warning("Detected unclean shutdown — previous session may need recovery")
        }
        UserDefaults.standard.set(false, forKey: key)
    }

    /// Mark clean shutdown (call on app termination).
    func markCleanShutdown() {
        UserDefaults.standard.set(true, forKey: "ghostset.cleanShutdown")
        saveInBackground()
        autoSaveTimer?.invalidate()
    }

    // MARK: - Update Workspace

    /// Update a workspace in-place (e.g. tags, agent).
    func updateWorkspace(_ workspace: Workspace) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces[idx] = workspace
        saveInBackground()
    }

    // MARK: - Environment Profiles (global)

    /// The currently active environment profile.
    var activeProfile: EnvironmentProfile? {
        guard let id = activeProfileID else { return nil }
        return environmentProfiles.first { $0.id == id }
    }

    /// The effective env vars: active profile's variables.
    var activeEnvironmentVariables: [String: String] {
        activeProfile?.variables ?? [:]
    }

    func saveEnvironmentProfiles() {
        let profiles = environmentProfiles
        let profileID = activeProfileID
        DispatchQueue.global(qos: .utility).async { [persistence] in
            persistence.saveEnvironmentProfiles(profiles, activeProfileID: profileID)
        }
    }

    func setActiveProfile(_ profileID: UUID?) {
        activeProfileID = profileID
        saveEnvironmentProfiles()
    }

    func upsertEnvironmentProfile(_ profile: EnvironmentProfile) {
        if let idx = environmentProfiles.firstIndex(where: { $0.id == profile.id }) {
            environmentProfiles[idx] = profile
        } else {
            environmentProfiles.append(profile)
        }
        saveEnvironmentProfiles()
    }

    func removeEnvironmentProfile(_ profile: EnvironmentProfile) {
        environmentProfiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id { activeProfileID = nil }
        saveEnvironmentProfiles()
    }

    // MARK: - Tag Registry

    /// Look up the definition for a tag name, falling back to a default gray tag.
    func tagDefinition(for name: String) -> TagDefinition {
        tagDefinitions.first { $0.name == name }
            ?? TagDefinition(name: name, colorName: "secondary")
    }

    /// Add or update a tag definition in the registry.
    func upsertTagDefinition(_ definition: TagDefinition) {
        if let idx = tagDefinitions.firstIndex(where: { $0.name == definition.name }) {
            tagDefinitions[idx] = definition
        } else {
            tagDefinitions.append(definition)
        }
        saveInBackground()
    }

    /// Remove a tag definition and strip it from all workspaces.
    func removeTagDefinition(_ name: String) {
        tagDefinitions.removeAll { $0.name == name }
        workspaces = workspaces.map { ws in
            guard ws.tags.contains(name) else { return ws }
            var updated = ws
            updated.tags.removeAll { $0 == name }
            return updated
        }
        saveInBackground()
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
        agent: AgentType? = nil,
        tags: [String] = [],
        taskDescription: String? = nil
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
            agent: agent,
            tags: tags,
            taskDescription: taskDescription
        )
        let readyWorkspace = withStatus(workspace, .ready)

        await MainActor.run {
            workspaces.append(readyWorkspace)
            persistence.save(workspaces)
        }

        return readyWorkspace
    }

    // MARK: - Register Existing Project

    /// Registers an existing git repository or worktree as a workspace
    /// without creating a new worktree.
    func registerExistingProject(path: String) async throws -> Workspace {
        let resolvedPath = (path as NSString).expandingTildeInPath

        // Validate it's a git repo or worktree
        let result = try await shell(
            "git", "-C", resolvedPath, "rev-parse", "--show-toplevel"
        )
        guard result.exitCode == 0 else {
            throw WorktreeError.creationFailed("Not a git repository: \(resolvedPath)")
        }

        let repoRoot = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // Get current branch
        let branchResult = try await shell(
            "git", "-C", resolvedPath, "rev-parse", "--abbrev-ref", "HEAD"
        )
        let branch = branchResult.exitCode == 0
            ? branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            : "main"

        let name = URL(fileURLWithPath: resolvedPath).lastPathComponent

        let workspace = Workspace(
            name: name,
            repoPath: repoRoot,
            worktreePath: resolvedPath,
            branch: branch
        )
        let readyWorkspace = withStatus(workspace, .ready)

        await MainActor.run {
            workspaces.append(readyWorkspace)
            saveInBackground()
        }

        return readyWorkspace
    }

    // MARK: - Remove / Delete Workspace

    /// Stop tracking a workspace without deleting files from disk.
    func untrackWorkspace(_ workspace: Workspace) {
        workspaces.removeAll { $0.id == workspace.id }
        saveInBackground()
    }

    /// Deletes a workspace: removes worktree from disk, optionally deletes branch.
    func deleteWorkspace(_ workspace: Workspace, deleteBranch: Bool = false) async throws {
        // Run onDestroy lifecycle command before removing
        if let cmd = workspace.onDestroyCommand, !cmd.isEmpty {
            runLifecycleCommand(cmd, in: workspace.worktreePath)
        }

        // Remove the git worktree from disk
        try await gitWorktreeRemove(repo: workspace.repoPath, path: workspace.worktreePath)

        // Optionally delete the branch
        if deleteBranch {
            try await gitBranchDelete(repo: workspace.repoPath, branch: workspace.branch)
        }

        await MainActor.run {
            workspaces.removeAll { $0.id == workspace.id }
            saveInBackground()
        }
    }

    /// Legacy alias — calls deleteWorkspace.
    func removeWorkspace(_ workspace: Workspace, deleteBranch: Bool = false) async throws {
        try await deleteWorkspace(workspace, deleteBranch: deleteBranch)
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

    /// Triggers a UI refresh — publishes change to drive SwiftUI re-renders.
    /// Views that display git stats will reload via their `.task` modifiers.
    func refreshStats() {
        objectWillChange.send()
    }

    // MARK: - Git Operations (private)

    private func gitWorktreeAdd(
        repo: String,
        path: String,
        branch: String,
        baseBranch: String
    ) async throws {
        // Check if branch already exists
        let branchCheck = try await shell(
            "git", "-C", repo, "rev-parse", "--verify", branch
        )

        let result: ShellResult
        if branchCheck.exitCode == 0 {
            // Branch exists — reuse it
            result = try await shell(
                "git", "-C", repo, "worktree", "add", path, branch
            )
        } else {
            // Create new branch from base
            result = try await shell(
                "git", "-C", repo, "worktree", "add", "-b", branch, path, baseBranch
            )
        }

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

    // MARK: - Lifecycle Commands

    /// Run a lifecycle command (onCreate/onDestroy) in the given working directory.
    /// Runs asynchronously on a background queue; failures are logged, not thrown.
    func runLifecycleCommand(_ command: String, in workingDirectory: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let stderr = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            process.standardError = stderr

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? ""
                    Ghostty.logger.warning("Lifecycle command failed (\(process.terminationStatus)): \(errStr)")
                }
            } catch {
                Ghostty.logger.warning("Lifecycle command error: \(error)")
            }
        }
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

    /// Reorder workspaces via drag & drop.
    func moveWorkspaces(from source: IndexSet, to destination: Int) {
        workspaces.move(fromOffsets: source, toOffset: destination)
        saveInBackground()
    }

    // MARK: - Rename Workspace

    func renameWorkspace(_ workspace: Workspace, to newName: String) {
        let updated = workspace.renamed(to: newName)
        updateWorkspace(updated)
    }

    // MARK: - Pin / Archive

    func togglePin(_ workspace: Workspace) {
        let updated = workspace.toggledPin()
        updateWorkspace(updated)
    }

    func toggleArchive(_ workspace: Workspace) {
        let updated = workspace.toggledArchive()
        updateWorkspace(updated)
    }

    // MARK: - Batch Operations

    func batchApplyTags(_ tags: [String], to workspaceIDs: Set<UUID>) {
        workspaces = workspaces.map { ws in
            guard workspaceIDs.contains(ws.id) else { return ws }
            var updated = ws
            let combined = Set(updated.tags + tags)
            updated.tags = Array(combined).sorted()
            return updated
        }
        saveInBackground()
    }

    func batchArchive(_ workspaceIDs: Set<UUID>) {
        workspaces = workspaces.map { ws in
            guard workspaceIDs.contains(ws.id) else { return ws }
            var updated = ws
            updated.isArchived = true
            return updated
        }
        saveInBackground()
    }

    func batchDelete(_ workspaceIDs: Set<UUID>) async {
        for id in workspaceIDs {
            guard let ws = workspaces.first(where: { $0.id == id }) else { continue }
            try? await deleteWorkspace(ws)
        }
    }

    // MARK: - Template Management

    func saveTemplate(_ template: WorkspaceTemplate) {
        if let idx = templates.firstIndex(where: { $0.id == template.id }) {
            templates[idx] = template
        } else {
            templates.append(template)
        }
        DispatchQueue.global(qos: .utility).async { [templatePersistence, templates] in
            templatePersistence.save(templates)
        }
    }

    func removeTemplate(_ template: WorkspaceTemplate) {
        templates.removeAll { $0.id == template.id }
        DispatchQueue.global(qos: .utility).async { [templatePersistence, templates] in
            templatePersistence.save(templates)
        }
    }

    func replaceAllTemplates(_ newTemplates: [WorkspaceTemplate]) {
        templates = newTemplates
        DispatchQueue.global(qos: .utility).async { [templatePersistence, templates] in
            templatePersistence.save(templates)
        }
    }

    func saveAsTemplate(_ workspace: Workspace, tabGroup: WorkspaceTabGroup? = nil) {
        let template: WorkspaceTemplate
        if let tabGroup {
            template = WorkspaceTemplate.snapshot(workspace: workspace, tabGroup: tabGroup)
        } else {
            template = WorkspaceTemplate.from(workspace: workspace)
        }
        saveTemplate(template)
    }

    // MARK: - Background Persistence

    /// Save state to disk on a background queue to avoid blocking the main thread.
    private func saveInBackground() {
        let workspacesSnapshot = workspaces
        let tagsSnapshot = tagDefinitions
        DispatchQueue.global(qos: .utility).async { [persistence] in
            persistence.save(workspacesSnapshot, tagDefinitions: tagsSnapshot)
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
