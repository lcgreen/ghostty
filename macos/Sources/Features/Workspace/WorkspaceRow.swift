import SwiftUI

/// A single row in the workspace sidebar — minimal dark aesthetic.
struct WorkspaceRow: View {
    let workspace: Workspace
    let tagLookup: (String) -> TagDefinition
    var hasUnread: Bool = false

    @State private var changeStats: WorkspaceChangeStats = .zero
    @State private var isAnimatingStatus = false
    @State private var isExpanded = false
    @State private var lastCommitTime: String?
    @State private var changedFileNames: [String] = []
    @State private var isAgentRunning = false
    @State private var hasConflicts = false
    @State private var branchAge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            mainRow

            // Expanded detail
            if isExpanded {
                expandedDetail
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
        .opacity(workspace.isArchived ? 0.5 : 1.0)
        .help(hoverTooltip)
        .task(id: workspace.id) {
            await loadAllStats()
        }
        .onAppear {
            isAnimatingStatus = hasUnread
        }
        .onChange(of: hasUnread) { newValue in
            isAnimatingStatus = newValue
        }
        // Refresh stats when app becomes active
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await loadAllStats() }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            Task { await loadAllStats() }
        }
        // Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(accessibilityValue)
        // Swipe actions
        .swipeActions(edge: .leading) {
            Button {
                NotificationCenter.default.post(
                    name: Notification.Name("ghostset.togglePin"),
                    object: workspace.id
                )
            } label: {
                Label(workspace.isPinned ? "Unpin" : "Pin", systemImage: "pin")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button {
                NotificationCenter.default.post(
                    name: Notification.Name("ghostset.toggleArchive"),
                    object: workspace.id
                )
            } label: {
                Label(workspace.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }
            .tint(.purple)
        }
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(alignment: .center, spacing: 10) {
            agentIcon

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

                // Branch + last activity
                HStack(spacing: 6) {
                    if abbreviatedBranch != workspace.name {
                        Text(abbreviatedBranch)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let time = lastCommitTime {
                        Text(time)
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
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

            // Expand toggle
            if workspace.taskDescription != nil || workspace.tags.count > 3 || changeStats != .zero {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                }
                .buttonStyle(.plain)
            }

            // Status + stats
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 3) {
                    if hasConflicts {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 7))
                            .foregroundColor(.red)
                    }
                    if isAgentRunning {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    } else {
                        Circle()
                            .fill(hasUnread ? Color.orange : statusColor)
                            .frame(width: 6, height: 6)
                    }
                }
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
    }

    // MARK: - Expanded Detail (double-click)

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Task description
            if let task = workspace.taskDescription, !task.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Text(task)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            // Branch with copy button
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                Text(workspace.branch)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(workspace.branch, forType: .string)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 7))
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.plain)
                .help("Copy branch name")
            }

            // Worktree path
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                Text(workspace.worktreePath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            // Health indicators
            HStack(spacing: 8) {
                if hasConflicts {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.red)
                        Text("Merge conflicts")
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                    }
                }
                if let age = branchAge {
                    Text("Branch: \(age)")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                if isAgentRunning {
                    HStack(spacing: 2) {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                        Text("Agent running")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                    }
                }
            }

            // Full tag list (if more than 3)
            if workspace.tags.count > 3 {
                HStack(spacing: 3) {
                    ForEach(workspace.tags, id: \.self) { tagName in
                        tagPill(tagName)
                    }
                }
            }

            // Changed files list
            if !changedFileNames.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(changedFileNames.count) changed files")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                    ForEach(changedFileNames.prefix(8), id: \.self) { file in
                        Text(file)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if changedFileNames.count > 8 {
                        Text("+ \(changedFileNames.count - 8) more")
                            .font(.system(size: 8))
                            .foregroundStyle(.quaternary)
                    }
                }
            }
        }
        .padding(.leading, 24)
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
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
        let prefixes = ["ghostset/", "feature/", "bugfix/", "hotfix/", "release/", "chore/", "fix/", "feat/"]
        for prefix in prefixes {
            if branch.hasPrefix(prefix) {
                return String(branch.dropFirst(prefix.count))
            }
        }
        return branch
    }

    private func tagPill(_ name: String) -> some View {
        let def = tagLookup(name)
        return Text(name)
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
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
        case .deleting: return .orange
        case .error: return .red
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts = ["Workspace \(workspace.name)"]
        if let agent = workspace.agent { parts.append("Agent: \(agent.displayName)") }
        if workspace.isPinned { parts.append("Pinned") }
        if workspace.isArchived { parts.append("Archived") }
        return parts.joined(separator: ", ")
    }

    private var accessibilityValue: String {
        var parts = ["Branch: \(workspace.branch)"]
        if changeStats != .zero {
            parts.append("\(changeStats.filesChanged) files changed")
        }
        if hasUnread { parts.append("Has unread activity") }
        parts.append("Status: \(workspace.status.displayLabel)")
        return parts.joined(separator: ", ")
    }

    private var hoverTooltip: String {
        var parts = ["Branch: \(workspace.branch)"]
        if changeStats != .zero {
            parts.append("\(changeStats.filesChanged) files, +\(changeStats.additions) -\(changeStats.deletions)")
        }
        if let time = lastCommitTime {
            parts.append("Last commit: \(time)")
        }
        parts.append("Status: \(workspace.status.displayLabel)")
        if let task = workspace.taskDescription {
            parts.append("Task: \(task)")
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Data Loading

    private func loadAllStats() async {
        let path = workspace.worktreePath
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard !Task.isCancelled else { return }

        // Change stats
        if let output = await GitShell.asyncOutput(["git", "-C", path, "diff", "--shortstat"]) {
            guard !Task.isCancelled else { return }
            changeStats = GitShell.parseShortstat(output)
        }

        // Last commit time
        if let output = await GitShell.asyncOutput(["git", "-C", path, "log", "-1", "--format=%cr"]) {
            guard !Task.isCancelled else { return }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lastCommitTime = trimmed }
        }

        // Changed file names (for expanded view)
        if let output = await GitShell.asyncOutput(["git", "-C", path, "diff", "--name-only"]) {
            guard !Task.isCancelled else { return }
            changedFileNames = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        }

        // Merge conflicts
        if let output = await GitShell.asyncOutput(["git", "-C", path, "diff", "--name-only", "--diff-filter=U"]) {
            guard !Task.isCancelled else { return }
            hasConflicts = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        // Branch age (how far behind main)
        if let output = await GitShell.asyncOutput(["git", "-C", path, "rev-list", "--count", "HEAD..main"]) {
            guard !Task.isCancelled else { return }
            let count = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            branchAge = count > 0 ? "\(count) behind main" : nil
        }

        // Agent process detection — find PIDs then check their cwd
        if workspace.agent != nil {
            let agentNames = ["claude", "codex", "copilot", "opencode", "gemini", "cursor"]
            var found = false
            for name in agentNames {
                guard !Task.isCancelled else { return }
                if let pids = await GitShell.asyncOutput(["pgrep", "-f", name]) {
                    let pidList = pids.trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: "\n").filter { !$0.isEmpty }
                    for pid in pidList {
                        guard !Task.isCancelled else { return }
                        if let lsofOut = await GitShell.asyncOutput(["lsof", "-p", pid, "-Fn"]) {
                            if lsofOut.contains(path) {
                                found = true
                                break
                            }
                        }
                    }
                }
                if found { break }
            }
            isAgentRunning = found
        }
    }
}
