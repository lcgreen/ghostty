import Foundation

/// Persists workspace state to disk so workspaces survive app restarts.
/// Stores data in ~/.ghostset/state.json
final class WorkspacePersistence {

    private let statePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ghostset/state.json"
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Load

    func load() -> [Workspace] {
        guard let data = FileManager.default.contents(atPath: statePath) else {
            return []
        }
        do {
            let state = try decoder.decode(PersistedState.self, from: data)
            return state.workspaces
        } catch {
            // Corrupted state file — log and start fresh
            print("[WorkspacePersistence] Failed to decode state: \(error)")
            return []
        }
    }

    // MARK: - Save

    func save(_ workspaces: [Workspace]) {
        let state = PersistedState(
            version: 1,
            lastUpdated: Date(),
            workspaces: workspaces
        )
        do {
            let data = try encoder.encode(state)
            let dir = (statePath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true
            )
            try data.write(to: URL(fileURLWithPath: statePath))
        } catch {
            print("[WorkspacePersistence] Failed to save state: \(error)")
        }
    }
    // MARK: - Session State

    private var sessionsDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ghostset/sessions"
    }

    /// Save a workspace's terminal session layout (split tree, working directories).
    func saveSession(_ session: WorkspaceSessionState) {
        let path = "\(sessionsDir)/\(session.workspaceID.uuidString).json"
        do {
            try FileManager.default.createDirectory(
                atPath: sessionsDir, withIntermediateDirectories: true
            )
            let data = try encoder.encode(session)
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            print("[WorkspacePersistence] Failed to save session: \(error)")
        }
    }

    /// Load a workspace's terminal session layout.
    func loadSession(workspaceID: UUID) -> WorkspaceSessionState? {
        let path = "\(sessionsDir)/\(workspaceID.uuidString).json"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? decoder.decode(WorkspaceSessionState.self, from: data)
    }

    /// Remove a workspace's session state.
    func removeSession(workspaceID: UUID) {
        let path = "\(sessionsDir)/\(workspaceID.uuidString).json"
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Window/Tab State

    private var windowStatePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ghostset/window-state.json"
    }

    /// Save the list of open workspace window tabs.
    func saveWindowState(_ state: WindowState) {
        do {
            let dir = (windowStatePath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true
            )
            let data = try encoder.encode(state)
            try data.write(to: URL(fileURLWithPath: windowStatePath))
        } catch {
            print("[WorkspacePersistence] Failed to save window state: \(error)")
        }
    }

    /// Load the saved window tab state.
    func loadWindowState() -> WindowState? {
        guard let data = FileManager.default.contents(atPath: windowStatePath) else { return nil }
        return try? decoder.decode(WindowState.self, from: data)
    }
}

/// Persisted state of all workspace window tabs.
struct WindowState: Codable {
    /// Each tab's selected workspace ID (nil = blank terminal tab).
    let tabs: [WindowTabState]
    let savedAt: Date

    init(tabs: [WindowTabState]) {
        self.tabs = tabs
        self.savedAt = Date()
    }
}

/// A single workspace window tab.
struct WindowTabState: Codable {
    let selectedWorkspaceID: UUID?
    let splitLayout: SplitLayout?
    let title: String?
    let agent: AgentType?
    /// Agent-specific session ID for precise resume (e.g. Claude session ID).
    let agentSessionID: String?
}

// MARK: - Persisted State

private struct PersistedState: Codable {
    let version: Int
    let lastUpdated: Date
    let workspaces: [Workspace]
}
