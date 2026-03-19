import SwiftUI

/// A compact, clean git status panel for the sidebar.
/// Shows branch info, flat file list with status indicators, and commit controls.
struct GitStatusPanel: View {
    let workspace: Workspace

    @State private var changedFiles: [GitFileChange] = []
    @State private var isLoading = false
    @State private var commitMessage = ""
    @State private var showingCommit = false
    @State private var expandedFile: String?
    @State private var diffText = ""
    @State private var branchName = ""
    @State private var ahead = 0
    @State private var behind = 0
    @State private var stashCount = 0
    @State private var hoveredFile: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            branchRow
            Divider().opacity(0.2)
            actionRow
            Divider().opacity(0.2)

            if isLoading {
                loadingState
            } else if changedFiles.isEmpty {
                emptyState
            } else {
                fileList
            }

            if showingCommit {
                Divider().opacity(0.2)
                commitBar
            }
        }
        .task(id: workspace.id) { await loadAll() }
        .onChange(of: workspace.id) { _ in
            // Reset state when switching workspaces
            changedFiles = []
            expandedFile = nil
            diffText = ""
            branchName = ""
            ahead = 0
            behind = 0
            stashCount = 0
            showingCommit = false
            commitMessage = ""
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in Task { await loadAll() } }
    }

    // MARK: - Branch Row

    private var branchRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            Text(branchName.isEmpty ? workspace.branch : branchName)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 2)

            if ahead > 0 {
                badge("↑\(ahead)", color: .green)
            }
            if behind > 0 {
                badge("↓\(behind)", color: .orange)
            }
            if stashCount > 0 {
                badge("⊡\(stashCount)", color: .purple)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(color.opacity(0.9))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.1))
            .cornerRadius(3)
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 0) {
            let fileCount = changedFiles.count
            let staged = stagedCount

            if fileCount > 0 {
                Text("\(fileCount) changed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                if staged > 0 {
                    Text(" · \(staged) staged")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Clean")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            if fileCount > 0 {
                actionButton("plus.circle", help: "Stage all") { await stageAll() }
                actionButton("minus.circle", help: "Unstage all") { await unstageAll() }
            }

            actionButton("tray.and.arrow.down", help: "Stash") { await stash() }
            actionButton("arrow.clockwise", help: "Refresh") { await loadAll() }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showingCommit.toggle() }
            } label: {
                Image(systemName: showingCommit ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 10))
                    .foregroundColor(showingCommit ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(changedFiles.isEmpty)
            .help("Commit")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func actionButton(_ icon: String, help: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - File List (flat, with short relative paths)

    private var fileList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(changedFiles) { file in
                    VStack(alignment: .leading, spacing: 0) {
                        fileRow(file)
                        if expandedFile == file.path {
                            diffPreview
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 280)
    }

    private func fileRow(_ file: GitFileChange) -> some View {
        let isHovered = hoveredFile == file.path
        let isExpanded = expandedFile == file.path

        return HStack(spacing: 6) {
            // Status indicator
            Text(file.status.symbol)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(file.status.color)
                .frame(width: 10, alignment: .center)

            // Staged dot
            if file.isStaged {
                Circle()
                    .fill(Color.green.opacity(0.7))
                    .frame(width: 4, height: 4)
            } else {
                Color.clear.frame(width: 4, height: 4)
            }

            // Just the filename — full path in tooltip
            Text(URL(fileURLWithPath: file.path).lastPathComponent)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(file.path)

            Spacer(minLength: 2)

            // Stage/unstage on hover
            if isHovered || isExpanded {
                Button { Task { await toggleStage(file) } } label: {
                    Image(systemName: file.isStaged ? "minus.circle" : "plus.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(file.isStaged ? .orange : .green)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(isExpanded ? Color.blue.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hoveredFile = $0 ? file.path : nil }
        .onTapGesture { Task { await toggleDiff(for: file) } }
    }


    // MARK: - Diff Preview

    private var diffPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                let lines = diffText.components(separatedBy: "\n")
                    .filter { !$0.hasPrefix("diff ") && !$0.hasPrefix("index ") && !$0.hasPrefix("---") && !$0.hasPrefix("+++") }
                    .prefix(60)

                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(diffLineColor(line))
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 140)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(4)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func diffLineColor(_ line: String) -> Color {
        if line.hasPrefix("@@") { return .cyan.opacity(0.7) }
        if line.hasPrefix("+") { return .green.opacity(0.85) }
        if line.hasPrefix("-") { return .red.opacity(0.85) }
        return .primary.opacity(0.5)
    }

    // MARK: - Commit Bar

    private var commitBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                commitTemplateMenu

                TextField("Commit message...", text: $commitMessage)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
            }

            HStack(spacing: 6) {
                if stagedCount > 0 {
                    Text("\(stagedCount) staged")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Commit") { Task { await commit() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .disabled(commitMessage.isEmpty || stagedCount == 0)
                Button("Push") { Task { await push() } }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var commitTemplateMenu: some View {
        Menu {
            ForEach(ConventionalCommit.prefixes, id: \.label) { prefix in
                Button {
                    commitMessage = prefix.label + " " + commitMessage
                } label: {
                    Text("\(prefix.emoji) \(prefix.label)")
                }
            }
        } label: {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 18)
    }

    // MARK: - States

    private var loadingState: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Loading...").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
    }

    private var emptyState: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 10))
                .foregroundStyle(.green.opacity(0.6))
            Text("Working tree clean")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
    }

    // MARK: - Computed

    private var stagedCount: Int { changedFiles.filter(\.isStaged).count }

    // MARK: - Git Operations

    private func loadAll() async {
        async let s: Void = loadStatus()
        async let b: Void = loadBranchInfo()
        async let t: Void = loadStashCount()
        _ = await (s, b, t)
    }

    private func loadStatus() async {
        isLoading = true
        defer { isLoading = false }
        let path = workspace.worktreePath
        guard let output = await GitShell.asyncOutput(
            ["git", "-C", path, "status", "--porcelain"]
        ) else { return }
        changedFiles = output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .map { line in
                let statusChar = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
                let filePath = String(line.dropFirst(3))
                let isStaged = line.first != " " && line.first != "?"
                return GitFileChange(
                    path: filePath,
                    status: GitFileStatus.from(statusChar),
                    isStaged: isStaged
                )
            }
    }

    private func loadBranchInfo() async {
        let path = workspace.worktreePath
        if let name = await GitShell.asyncOutput(
            ["git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD"]
        ) { branchName = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let counts = await GitShell.asyncOutput(
            ["git", "-C", path, "rev-list", "--count", "--left-right", "@{upstream}...HEAD"]
        ) {
            let parts = counts.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\t")
            behind = Int(parts.first ?? "") ?? 0
            ahead = Int(parts.last ?? "") ?? 0
        }
    }

    private func loadStashCount() async {
        let path = workspace.worktreePath
        if let output = await GitShell.asyncOutput(["git", "-C", path, "stash", "list"]) {
            stashCount = output.components(separatedBy: "\n").filter { !$0.isEmpty }.count
        }
    }

    private func toggleStage(_ file: GitFileChange) async {
        let path = workspace.worktreePath
        if file.isStaged {
            _ = await GitShell.asyncOutput(["git", "-C", path, "reset", "HEAD", file.path])
        } else {
            _ = await GitShell.asyncOutput(["git", "-C", path, "add", file.path])
        }
        await loadStatus()
    }

    private func stageAll() async {
        _ = await GitShell.asyncOutput(["git", "-C", workspace.worktreePath, "add", "-A"])
        await loadStatus()
    }

    private func unstageAll() async {
        _ = await GitShell.asyncOutput(["git", "-C", workspace.worktreePath, "reset", "HEAD"])
        await loadStatus()
    }

    private func stash() async {
        _ = await GitShell.asyncOutput(["git", "-C", workspace.worktreePath, "stash"])
        await loadAll()
    }

    private func commit() async {
        let msg = commitMessage
        _ = await GitShell.asyncOutput(["git", "-C", workspace.worktreePath, "commit", "-m", msg])
        commitMessage = ""
        await loadStatus()
    }

    private func push() async {
        _ = await GitShell.asyncOutput(["git", "-C", workspace.worktreePath, "push"])
    }

    private func toggleDiff(for file: GitFileChange) async {
        if expandedFile == file.path {
            expandedFile = nil
            diffText = ""
            return
        }
        expandedFile = file.path
        let output = await GitShell.asyncOutput(
            ["git", "-C", workspace.worktreePath, "diff", "--", file.path]
        )
        diffText = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No diff available"
    }
}

// MARK: - Models

struct GitFileChange: Identifiable {
    let path: String
    let status: GitFileStatus
    var isStaged: Bool
    var id: String { path }
    var filename: String { path.components(separatedBy: "/").last ?? path }
}

enum GitFileStatus {
    case modified, added, deleted, renamed, untracked, conflicted

    var symbol: String {
        switch self {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .untracked: return "?"
        case .conflicted: return "U"
        }
    }

    var color: Color {
        switch self {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .renamed: return .blue
        case .untracked: return .secondary
        case .conflicted: return .red
        }
    }

    static func from(_ s: String) -> GitFileStatus {
        if s.contains("M") { return .modified }
        if s.contains("A") { return .added }
        if s.contains("D") { return .deleted }
        if s.contains("R") { return .renamed }
        if s.contains("U") { return .conflicted }
        return .untracked
    }
}
