import SwiftUI

/// A single row in the workspace sidebar.
/// Shows agent icon, name, branch, status, and change stats.
struct WorkspaceRow: View {
    let workspace: Workspace
    @State private var changeStats: WorkspaceChangeStats = .zero

    var body: some View {
        HStack(spacing: 8) {
            agentIcon
            nameAndBranch
            Spacer()
            trailingInfo
        }
        .padding(.vertical, 2)
        .task {
            await loadChangeStats()
        }
    }

    // MARK: - Agent Icon

    private var agentIcon: some View {
        Group {
            if let agent = workspace.agent {
                Image(systemName: agent.iconName)
                    .font(.body)
                    .foregroundColor(agentColor(agent))
            } else {
                Image(systemName: "terminal")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 20)
    }

    // MARK: - Name and Branch

    private var nameAndBranch: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workspace.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(workspace.branch)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !workspace.tags.isEmpty {
                    ForEach(workspace.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(3)
                    }
                }
            }
        }
    }

    // MARK: - Trailing Info (status + changes)

    private var trailingInfo: some View {
        VStack(alignment: .trailing, spacing: 1) {
            statusIndicator

            if changeStats != .zero {
                HStack(spacing: 4) {
                    if changeStats.additions > 0 {
                        Text("+\(changeStats.additions)")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    if changeStats.deletions > 0 {
                        Text("-\(changeStats.deletions)")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        Image(systemName: workspace.status.iconName)
            .font(.caption2)
            .foregroundColor(statusColor)
    }

    private var statusColor: Color {
        switch workspace.status {
        case .creating: return .secondary
        case .ready: return .blue
        case .running: return .green
        case .stopped: return .gray
        case .error: return .red
        }
    }

    // MARK: - Helpers

    private func agentColor(_ agent: AgentType) -> Color {
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

    private func loadChangeStats() async {
        // Shell out to git diff --shortstat in the worktree
        // This runs in a background task so it doesn't block the UI
        guard FileManager.default.fileExists(atPath: workspace.worktreePath) else { return }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", workspace.worktreePath, "diff", "--shortstat"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            changeStats = parseShortstat(output)
        } catch {
            // Silently ignore — stats are cosmetic
        }
    }

    /// Parses "3 files changed, 46 insertions(+), 12 deletions(-)"
    private func parseShortstat(_ output: String) -> WorkspaceChangeStats {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .zero }

        var files = 0, adds = 0, dels = 0
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
