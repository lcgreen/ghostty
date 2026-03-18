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
}

// MARK: - Persisted State

private struct PersistedState: Codable {
    let version: Int
    let lastUpdated: Date
    let workspaces: [Workspace]
}
