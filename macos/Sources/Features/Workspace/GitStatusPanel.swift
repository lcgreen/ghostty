import SwiftUI

/// VS Code-style source control panel — commit message at top, push button,
/// staged/unstaged sections, files grouped by directory with line counts.
struct GitStatusPanel: View {
    let workspace: Workspace

    @State private var changedFiles: [GitFileChange] = []
    @State private var isLoading = false
    @State private var commitMessage = ""
    @State private var stagedExpanded = true
    @State private var unstagedExpanded = true
    @State private var branchName = ""
    @State private var ahead = 0
    @State private var behind = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                loadingState
            } else if changedFiles.isEmpty {
                emptyState
            } else {
                commitInput
                Divider().opacity(0.2)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(changedFiles) { file in
                            fileRow(file, action: { f in
                                if f.isStaged { await unstage(f) } else { await stage(f) }
                            })
                        }
                    }
                }
            }
        }
        .task(id: workspace.id) { await loadAll() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in Task { await loadAll() } }
    }

    // MARK: - Computed

    private var stagedFiles: [GitFileChange] {
        changedFiles.filter(\.isStaged)
    }

    private var unstagedFiles: [GitFileChange] {
        changedFiles.filter { !$0.isStaged }
    }

    /// Group files by their directory path.
    private func groupedByDir(_ files: [GitFileChange]) -> [(dir: String, files: [GitFileChange])] {
        var groups: [String: [GitFileChange]] = [:]
        for file in files {
            let dir = directoryOf(file.path)
            groups[dir, default: []].append(file)
        }
        return groups.sorted { $0.key < $1.key }.map { (dir: $0.key, files: $0.value) }
    }

    private func directoryOf(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count <= 1 { return "." }
        return components.dropLast().joined(separator: "/")
    }

    // MARK: - Commit Input

    private var commitInput: some View {
        HStack(spacing: 4) {
            TextField("Commit message", text: $commitMessage)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(4)

            // Commit button (only when message + staged files)
            if !commitMessage.isEmpty && !stagedFiles.isEmpty {
                Button { Task { await commit() } } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
            }

            // Push button
            Button { Task { await push() } } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Section View

    private func sectionView(
        title: String,
        count: Int,
        files: [GitFileChange],
        isExpanded: Binding<Bool>,
        stageAction: @escaping () async -> Void,
        stageIcon: String,
        fileAction: @escaping (GitFileChange) async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 10)

                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Text("\(count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Spacer()

                // Stage/unstage all button
                Button { Task { await stageAction() } } label: {
                    Image(systemName: stageIcon)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)

                // Refresh
                Button { Task { await loadAll() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            // Files (flat list, no directory grouping)
            if isExpanded.wrappedValue {
                ForEach(files) { file in
                    fileRow(file, action: fileAction)
                }
            }
        }
    }

    // MARK: - File Row

    private func fileRow(
        _ file: GitFileChange,
        action: @escaping (GitFileChange) async -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: file.status.iconName)
                .font(.system(size: 8))
                .foregroundColor(file.status.color)
                .frame(width: 10)

            Text(file.path)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)

            Spacer(minLength: 2)

            if file.additions > 0 {
                Text("+\(file.additions)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.green)
            }
            if file.deletions > 0 {
                Text("-\(file.deletions)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.red)
            }

            Button { Task { await action(file) } } label: {
                Image(systemName: file.isStaged ? "minus" : "plus")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }

    // MARK: - States

    private var loadingState: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Loading...").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
    }

    private var emptyState: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 10))
                .foregroundColor(.green.opacity(0.6))
            Text("Working tree clean")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
    }

    // MARK: - Git Operations

    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }

        let path = workspace.worktreePath
        guard FileManager.default.fileExists(atPath: path) else { return }

        // Load status with numstat for line counts
        async let statusTask: Void = loadStatus(path: path)
        async let branchTask: Void = loadBranch(path: path)
        _ = await (statusTask, branchTask)
    }

    private func loadStatus(path: String) async {
        // Get file statuses
        guard let statusOutput = await gitAsync(["git", "-C", path, "status", "--porcelain"]) else { return }

        // Get line counts via numstat
        let numstatOutput = await gitAsync(["git", "-C", path, "diff", "--numstat"]) ?? ""
        var lineCounts: [String: (adds: Int, dels: Int)] = [:]
        for line in numstatOutput.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 3 {
                lineCounts[parts[2]] = (adds: Int(parts[0]) ?? 0, dels: Int(parts[1]) ?? 0)
            }
        }

        changedFiles = statusOutput.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .map { line in
                let statusChar = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
                let filePath = String(line.dropFirst(3))
                let isStaged = line.first != " " && line.first != "?"
                let counts = lineCounts[filePath]
                return GitFileChange(
                    path: filePath,
                    status: GitFileStatus.from(statusChar),
                    isStaged: isStaged,
                    additions: counts?.adds ?? 0,
                    deletions: counts?.dels ?? 0
                )
            }
    }

    private func loadBranch(path: String) async {
        if let name = await gitAsync(["git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD"]) {
            branchName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let counts = await gitAsync(
            ["git", "-C", path, "rev-list", "--count", "--left-right", "@{upstream}...HEAD"]
        ) {
            let parts = counts.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\t")
            behind = Int(parts.first ?? "") ?? 0
            ahead = Int(parts.last ?? "") ?? 0
        }
    }

    private func stage(_ file: GitFileChange) async {
        _ = await gitAsync(["git", "-C", workspace.worktreePath, "add", file.path])
        await loadStatus(path: workspace.worktreePath)
    }

    private func unstage(_ file: GitFileChange) async {
        _ = await gitAsync(["git", "-C", workspace.worktreePath, "reset", "HEAD", file.path])
        await loadStatus(path: workspace.worktreePath)
    }

    private func stageAll() async {
        _ = await gitAsync(["git", "-C", workspace.worktreePath, "add", "-A"])
        await loadStatus(path: workspace.worktreePath)
    }

    private func unstageAll() async {
        _ = await gitAsync(["git", "-C", workspace.worktreePath, "reset", "HEAD"])
        await loadStatus(path: workspace.worktreePath)
    }

    private func commit() async {
        let msg = commitMessage
        _ = await gitAsync(["git", "-C", workspace.worktreePath, "commit", "-m", msg])
        commitMessage = ""
        await loadStatus(path: workspace.worktreePath)
    }

    private func push() async {
        _ = await gitAsync(["git", "-C", workspace.worktreePath, "push"])
    }

    // MARK: - Shell

    private func gitAsync(_ args: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process(); let pipe = Pipe()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                p.arguments = args; p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                do {
                    try p.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    guard p.terminationStatus == 0 else { continuation.resume(returning: nil); return }
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } catch { continuation.resume(returning: nil) }
            }
        }
    }
}

// MARK: - Models

struct GitFileChange: Identifiable {
    let path: String
    let status: GitFileStatus
    var isStaged: Bool
    var additions: Int = 0
    var deletions: Int = 0

    var id: String { path }
    var filename: String { URL(fileURLWithPath: path).lastPathComponent }
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

    var iconName: String {
        switch self {
        case .modified: return "square.fill"
        case .added: return "plus.square.fill"
        case .deleted: return "minus.square.fill"
        case .renamed: return "arrow.right.square.fill"
        case .untracked: return "plus.square"
        case .conflicted: return "exclamationmark.square.fill"
        }
    }

    var color: Color {
        switch self {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .renamed: return .blue
        case .untracked: return .green
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
