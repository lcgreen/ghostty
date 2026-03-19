import SwiftUI

/// Cross-workspace diff comparison view — see changes from multiple workspaces side by side.
struct WorkspaceDiffView: View {
    @ObservedObject var manager: WorktreeManager
    @Environment(\.dismiss) private var dismiss

    @State private var diffs: [WorkspaceDiff] = []
    @State private var isLoading = false
    @State private var expandedFiles: Set<String> = []
    @State private var inlineDiffs: [String: String] = [:]

    // Filtering
    @State private var selectedExtensions: Set<String> = []
    @State private var selectedStatuses: Set<String> = ["M", "A", "D", "R"]
    @State private var selectedWorkspaces: Set<UUID> = []

    // Compare mode
    @State private var compareMode = false
    @State private var compareLeft: UUID?
    @State private var compareRight: UUID?
    @State private var comparisonDiff: String?

    // Merge
    @State private var mergeTarget: WorkspaceDiff?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filterBar
            Divider()
            if compareMode { comparisonSection } else { diffList }
        }
        .frame(width: 640, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await loadAllDiffs() }
        .alert("Merge to main?", isPresented: .init(
            get: { mergeTarget != nil },
            set: { if !$0 { mergeTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { mergeTarget = nil }
            Button("Merge", role: .destructive) {
                if let target = mergeTarget { Task { await merge(target) } }
            }
        } message: {
            if let t = mergeTarget {
                Text("Merge branch '\(t.workspace.branch)' into main?")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Workspace Changes").font(.system(size: 14, weight: .semibold))
            Spacer()
            Toggle("Compare Two", isOn: $compareMode)
                .toggleStyle(.switch).controlSize(.mini)
            Button { Task { await loadAllDiffs() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    // MARK: - Filters

    private var allExtensions: [String] {
        let exts = diffs.flatMap(\.files).compactMap { URL(fileURLWithPath: $0.path).pathExtension }
            .filter { !$0.isEmpty }
        return Array(Set(exts)).sorted()
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            extensionFilterMenu
            ForEach(["M", "A", "D", "R"], id: \.self) { status in
                Toggle(status, isOn: Binding(
                    get: { selectedStatuses.contains(status) },
                    set: { if $0 { selectedStatuses.insert(status) } else { _ = selectedStatuses.remove(status) } }
                )).toggleStyle(.button).controlSize(.mini).tint(statusColor(status))
            }
            Spacer()
            workspaceFilterMenu
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var extensionFilterMenu: some View {
        Menu {
            ForEach(allExtensions, id: \.self) { ext in
                Button { toggleSet(&selectedExtensions, ext) } label: {
                    HStack { if selectedExtensions.contains(ext) { Image(systemName: "checkmark") }; Text(".\(ext)") }
                }
            }
            Divider(); Button("Clear") { selectedExtensions.removeAll() }
        } label: { Label("Type", systemImage: "doc").font(.system(size: 10)) }
            .menuStyle(.borderlessButton).frame(width: 60)
    }

    private var workspaceFilterMenu: some View {
        Menu {
            ForEach(diffs) { diff in
                Button { toggleSet(&selectedWorkspaces, diff.workspace.id) } label: {
                    HStack { if selectedWorkspaces.contains(diff.workspace.id) { Image(systemName: "checkmark") }; Text(diff.workspace.name) }
                }
            }
            Divider(); Button("Show All") { selectedWorkspaces.removeAll() }
        } label: { Label("Workspace", systemImage: "folder").font(.system(size: 10)) }
            .menuStyle(.borderlessButton).frame(width: 90)
    }

    private func toggleSet<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    // MARK: - Diff List

    private var filteredDiffs: [WorkspaceDiff] {
        diffs.filter { selectedWorkspaces.isEmpty || selectedWorkspaces.contains($0.workspace.id) }
            .map { diff in
                let filtered = diff.files.filter { file in
                    guard selectedStatuses.contains(file.status) else { return false }
                    if selectedExtensions.isEmpty { return true }
                    let ext = URL(fileURLWithPath: file.path).pathExtension
                    return selectedExtensions.contains(ext)
                }
                return WorkspaceDiff(workspace: diff.workspace, files: filtered,
                                     additions: filtered.reduce(0) { $0 + $1.additions },
                                     deletions: filtered.reduce(0) { $0 + $1.deletions })
            }
            .filter { !$0.files.isEmpty }
    }

    @ViewBuilder
    private var diffList: some View {
        if isLoading {
            ProgressView("Scanning workspaces...").controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 100)
        } else if filteredDiffs.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(.tertiary)
                Text("All workspaces clean").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredDiffs) { diff in diffSection(diff) }
                }
            }
        }
    }

    // MARK: - Diff Section per Workspace

    private func diffSection(_ diff: WorkspaceDiff) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let agent = diff.workspace.agent {
                    Image(systemName: agent.iconName).font(.system(size: 10))
                        .foregroundColor(AgentColors.color(for: agent))
                }
                Text(diff.workspace.name).font(.system(size: 12, weight: .semibold))
                Text(diff.workspace.branch)
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text("+\(diff.additions) -\(diff.deletions)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(diff.additions > 0 ? .green : .secondary)
                copyPatchButton(diff)
                mergeButton(diff)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))

            ForEach(diff.files, id: \.path) { file in
                fileRow(file, workspace: diff.workspace)
            }
            Divider().opacity(0.2).padding(.top, 4)
        }
    }

    private func fileRow(_ file: DiffFile, workspace: Workspace) -> some View {
        let key = "\(workspace.id):\(file.path)"
        let expanded = expandedFiles.contains(key)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(file.status).font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(statusColor(file.status)).frame(width: 12)
                Text(file.path).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer()
                if file.additions > 0 { Text("+\(file.additions)").font(.system(size: 9, design: .monospaced)).foregroundColor(.green) }
                if file.deletions > 0 { Text("-\(file.deletions)").font(.system(size: 9, design: .monospaced)).foregroundColor(.red) }
                Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 2).contentShape(Rectangle())
            .onTapGesture { Task { await toggleInlineDiff(key: key, workspace: workspace, filePath: file.path) } }
            if expanded, let content = inlineDiffs[key] {
                diffBlock(content).padding(.horizontal, 16).padding(.vertical, 4)
            }
        }
    }

    private func diffBlock(_ content: String) -> some View {
        let lines = content.components(separatedBy: "\n").prefix(80)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 9, design: .monospaced)).lineLimit(1)
                    .foregroundColor(diffLineColor(line)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(6).background(Color.primary.opacity(0.02)).cornerRadius(4)
    }

    // MARK: - Compare Two Workspaces

    @ViewBuilder
    private var comparisonSection: some View {
        HStack(spacing: 12) {
            workspacePicker("Left", selection: $compareLeft)
            workspacePicker("Right", selection: $compareRight)
            Button("Compare") { Task { await runComparison() } }
                .disabled(compareLeft == nil || compareRight == nil || compareLeft == compareRight)
        }.padding(12)
        if let output = comparisonDiff { ScrollView { diffBlock(output).padding(12) } }
        else { Spacer() }
    }

    private func workspacePicker(_ label: String, selection: Binding<UUID?>) -> some View {
        Picker(label, selection: selection) {
            Text("Select...").tag(nil as UUID?)
            ForEach(diffs) { d in Text(d.workspace.name).tag(d.workspace.id as UUID?) }
        }
    }

    // MARK: - Action Buttons

    private func copyPatchButton(_ diff: WorkspaceDiff) -> some View {
        Button { Task {
            guard let out = await GitShell.asyncOutput(["git", "-C", diff.workspace.worktreePath, "diff"]) else { return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(out, forType: .string)
        } } label: { Image(systemName: "doc.on.clipboard").font(.system(size: 9)) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("Copy as Patch")
    }

    private func mergeButton(_ diff: WorkspaceDiff) -> some View {
        Button { mergeTarget = diff } label: { Image(systemName: "arrow.triangle.merge").font(.system(size: 9)) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("Merge to main")
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "M": return .orange; case "A": return .green
        case "D": return .red; case "R": return .blue
        default: return .secondary
        }
    }

    private func diffLineColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return .secondary
    }

    // MARK: - Async Operations

    private func toggleInlineDiff(key: String, workspace: Workspace, filePath: String) async {
        if expandedFiles.contains(key) { expandedFiles.remove(key); return }
        if inlineDiffs[key] == nil {
            let output = await GitShell.asyncOutput(
                ["git", "-C", workspace.worktreePath, "diff", "--", filePath]
            )
            inlineDiffs[key] = output ?? "(no diff)"
        }
        expandedFiles.insert(key)
    }

    private func loadAllDiffs() async {
        isLoading = true
        defer { isLoading = false }
        var results: [WorkspaceDiff] = []
        for ws in manager.workspaces {
            if let diff = await loadDiff(for: ws), !diff.files.isEmpty {
                results.append(diff)
            }
        }
        diffs = results
    }

    private func loadDiff(for workspace: Workspace) async -> WorkspaceDiff? {
        guard let output = await GitShell.asyncOutput(
            ["git", "-C", workspace.worktreePath, "diff", "--numstat"]
        ) else { return nil }

        let files = output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> DiffFile? in
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 3 else { return nil }
                return DiffFile(path: parts[2], status: "M",
                                additions: Int(parts[0]) ?? 0, deletions: Int(parts[1]) ?? 0)
            }
        let totalAdds = files.reduce(0) { $0 + $1.additions }
        let totalDels = files.reduce(0) { $0 + $1.deletions }
        return WorkspaceDiff(workspace: workspace, files: files,
                             additions: totalAdds, deletions: totalDels)
    }

    private func merge(_ diff: WorkspaceDiff) async {
        _ = await GitShell.asyncOutput(
            ["git", "-C", diff.workspace.repoPath, "merge", diff.workspace.branch]
        )
        mergeTarget = nil
        await loadAllDiffs()
    }

    private func runComparison() async {
        guard let leftID = compareLeft, let rightID = compareRight,
              let left = diffs.first(where: { $0.workspace.id == leftID }),
              let right = diffs.first(where: { $0.workspace.id == rightID }) else { return }
        comparisonDiff = await GitShell.asyncOutput(
            ["git", "-C", left.workspace.repoPath, "diff",
             left.workspace.branch, right.workspace.branch]
        ) ?? "(no differences)"
    }
}

// MARK: - Models

struct WorkspaceDiff: Identifiable {
    let workspace: Workspace
    let files: [DiffFile]
    let additions: Int
    let deletions: Int
    var id: UUID { workspace.id }
}

struct DiffFile {
    let path: String
    let status: String
    let additions: Int
    let deletions: Int
}
