import Foundation

/// Per-workspace command history stored as append-only JSONL files.
/// Location: ~/.ghostset/history/{workspace-id}.jsonl
final class WorkspaceCommandHistory {

    private let maxEntries = 10_000
    private let historyDir: String

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.historyDir = "\(home)/.ghostset/history"
    }

    // MARK: - Read

    /// Load command history for a workspace.
    func load(workspaceID: UUID) -> [CommandHistoryEntry] {
        let path = filePath(for: workspaceID)
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        return content
            .split(separator: "\n")
            .compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(CommandHistoryEntry.self, from: lineData)
            }
    }

    /// Search command history for a workspace.
    func search(workspaceID: UUID, query: String) -> [CommandHistoryEntry] {
        let entries = load(workspaceID: workspaceID)
        guard !query.isEmpty else { return entries }
        let lowered = query.lowercased()
        return entries.filter { $0.command.lowercased().contains(lowered) }
    }

    // MARK: - Write

    /// Append a command to the workspace's history.
    func append(entry: CommandHistoryEntry) {
        ensureDirectory()

        let path = filePath(for: entry.workspaceID)
        guard let lineData = try? encoder.encode(entry),
              var line = String(data: lineData, encoding: .utf8) else { return }
        line += "\n"

        if FileManager.default.fileExists(atPath: path) {
            guard let handle = FileHandle(forWritingAtPath: path) else { return }
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8) ?? Data())
            handle.closeFile()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }

        rotateIfNeeded(workspaceID: entry.workspaceID)
    }

    // MARK: - Maintenance

    /// Trim history to maxEntries if it's grown too large.
    private func rotateIfNeeded(workspaceID: UUID) {
        let entries = load(workspaceID: workspaceID)
        guard entries.count > maxEntries else { return }

        // Keep the most recent entries
        let trimmed = Array(entries.suffix(maxEntries))
        let path = filePath(for: workspaceID)

        let lines = trimmed.compactMap { entry -> String? in
            guard let data = try? encoder.encode(entry) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        try? lines.joined(separator: "\n").appending("\n")
            .write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private func filePath(for workspaceID: UUID) -> String {
        "\(historyDir)/\(workspaceID.uuidString).jsonl"
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(
            atPath: historyDir,
            withIntermediateDirectories: true
        )
    }
}
