import SwiftUI

/// A single row in the workspace sidebar — minimal dark aesthetic.
struct WorkspaceRow: View {
    let workspace: Workspace
    let tagLookup: (String) -> TagDefinition
    var hasUnread: Bool = false

    @State private var changeStats: WorkspaceChangeStats = .zero
    @State private var isAnimatingStatus = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Agent icon
            agentIcon

            // Name + branch + tags
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if workspace.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.orange.opacity(0.7))
                    }
                    Text(workspace.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }

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
                    .fill(hasUnread ? Color.orange : statusColor)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isAnimatingStatus ? 1.5 : 1.0)
                    .animation(
                        isAnimatingStatus
                            ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                            : .default,
                        value: isAnimatingStatus
                    )

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
        .opacity(workspace.isArchived ? 0.5 : 1.0)
        .help(hoverTooltip)
        .task(id: workspace.id) {
            await loadChangeStats()
        }
        .onChange(of: hasUnread) { newValue in
            isAnimatingStatus = newValue
        }
    }

    // MARK: - Components

    private var agentIcon: some View {
        Group {
            if let agent = workspace.agent {
                Image(systemName: agent.iconName)
                    .font(.system(size: 11))
                    .foregroundColor(AgentColors.color(for: agent).opacity(0.9))
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

    private var hoverTooltip: String {
        var parts = ["Branch: \(workspace.branch)"]
        if changeStats != .zero {
            parts.append("\(changeStats.filesChanged) files, +\(changeStats.additions) -\(changeStats.deletions)")
        }
        parts.append("Status: \(workspace.status.displayLabel)")
        return parts.joined(separator: "\n")
    }

    // MARK: - Git Stats

    private func loadChangeStats() async {
        let worktreePath = workspace.worktreePath
        guard FileManager.default.fileExists(atPath: worktreePath) else { return }

        guard let output = await GitShell.asyncOutput(["git", "-C", worktreePath, "diff", "--shortstat"]) else { return }
        changeStats = GitShell.parseShortstat(output)
    }
}
