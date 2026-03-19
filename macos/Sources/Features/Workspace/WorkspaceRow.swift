import SwiftUI

/// A single row in the workspace sidebar — minimal dark aesthetic.
struct WorkspaceRow: View {
    let workspace: Workspace
    let tagLookup: (String) -> TagDefinition

    @State private var changeStats: WorkspaceChangeStats = .zero

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Agent icon
            agentIcon

            // Name + branch + tags
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                // Branch (only if different from name)
                if abbreviatedBranch != workspace.name {
                    Text(abbreviatedBranch)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Tags
                if !workspace.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(workspace.tags.prefix(3), id: \.self) { tagName in
                            tagPill(tagName)
                        }
                        if workspace.tags.count > 3 {
                            Text("+\(workspace.tags.count - 3)")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 1)
                }
            }

            Spacer(minLength: 4)

            // Status + stats
            VStack(alignment: .trailing, spacing: 3) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                if changeStats != .zero {
                    HStack(spacing: 2) {
                        if changeStats.additions > 0 {
                            Text("+\(changeStats.additions)")
                                .foregroundColor(.green.opacity(0.8))
                        }
                        if changeStats.deletions > 0 {
                            Text("-\(changeStats.deletions)")
                                .foregroundColor(.red.opacity(0.8))
                        }
                    }
                    .font(.system(size: 9, design: .monospaced))
                }
            }
        }
        .padding(.vertical, 6)
        .task {
            await loadChangeStats()
        }
    }

    // MARK: - Components

    private var agentIcon: some View {
        Group {
            if let agent = workspace.agent {
                Image(systemName: agent.iconName)
                    .font(.system(size: 11))
                    .foregroundColor(agentColor(agent).opacity(0.9))
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 14)
    }

    private var abbreviatedBranch: String {
        let branch = workspace.branch
        if branch.hasPrefix("ghostset/") {
            return String(branch.dropFirst("ghostset/".count))
        }
        return branch
    }

    private func tagPill(_ name: String) -> some View {
        let def = tagLookup(name)
        return Text(name)
            .font(.system(size: 9, weight: .medium))
            .fixedSize()
            .foregroundColor(def.color.opacity(0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(def.color.opacity(0.18))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(def.color.opacity(0.25), lineWidth: 0.5)
            )
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

    // MARK: - Git Stats

    private func loadChangeStats() async {
        let worktreePath = workspace.worktreePath
        guard FileManager.default.fileExists(atPath: worktreePath) else { return }

        let stats: WorkspaceChangeStats = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git", "-C", worktreePath, "diff", "--shortstat"]
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: self.parseShortstat(output))
                } catch {
                    continuation.resume(returning: .zero)
                }
            }
        }
        changeStats = stats
    }

    private func parseShortstat(_ output: String) -> WorkspaceChangeStats {
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
