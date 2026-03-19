import SwiftUI

/// Project creation mode.
enum ProjectMode: String, CaseIterable {
    case empty, clone, existing

    var title: String {
        switch self {
        case .empty: return "Empty"
        case .clone: return "Clone"
        case .existing: return "Existing"
        }
    }

    var subtitle: String {
        switch self {
        case .empty: return "New git repository from scratch"
        case .clone: return "Clone from a remote URL"
        case .existing: return "Add an existing project or worktree"
        }
    }

    var icon: String {
        switch self {
        case .empty: return "folder.badge.plus"
        case .clone: return "arrow.down.circle"
        case .existing: return "folder.badge.gearshape"
        }
    }
}

/// New Project sheet — the entry point for creating workspaces.
/// Supports Empty, Clone, and Template modes.
struct NewProjectSheet: View {
    @ObservedObject var manager: WorktreeManager
    let onCreated: (Workspace) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var mode: ProjectMode = .clone
    @State private var location = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ghostset/projects").path
    @State private var repoURL = ""
    @State private var repoName = ""
    @State private var existingPath = ""
    @State private var discoveredWorktrees: [DiscoveredWorktree] = []
    @State private var selectedWorktrees: Set<String> = []
    @State private var isScanning = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
            }
            footer
        }
        .frame(width: 520)
        .frame(minHeight: 380, maxHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Project")
                .font(.system(size: 20, weight: .bold))

            // Location
            VStack(alignment: .leading, spacing: 6) {
                Text("Location")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("", text: $location)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(8)
                        .background(fieldBackground)
                        .cornerRadius(8)

                    Button(action: browseLocation) {
                        Image(systemName: "folder")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(GhostsetButtonStyle())
                }
            }

            // Mode selector
            HStack(spacing: 10) {
                ForEach(ProjectMode.allCases, id: \.self) { m in
                    modeCard(m)
                }
            }

            // Mode-specific input
            modeInput
        }
        .padding(24)
    }

    // MARK: - Mode Cards

    private func modeCard(_ m: ProjectMode) -> some View {
        let isSelected = mode == m

        return Button(action: { withAnimation(.easeInOut(duration: 0.15)) { mode = m } }) {
            VStack(spacing: 8) {
                Image(systemName: m.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(m.title)
                    .font(.system(size: 12, weight: .semibold))

                Text(m.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                        lineWidth: 1
                    )
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mode Input

    @ViewBuilder
    private var modeInput: some View {
        switch mode {
        case .clone:
            VStack(alignment: .leading, spacing: 6) {
                Text("Repository URL")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("https:// or git@github.com:user/repo.git", text: $repoURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8)
                    .background(fieldBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                    )
            }

        case .empty:
            VStack(alignment: .leading, spacing: 6) {
                Text("Repository Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("my-project", text: $repoName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(8)
                    .background(fieldBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                    )
            }

        case .existing:
            VStack(alignment: .leading, spacing: 6) {
                Text("Repository")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("/path/to/repo", text: $existingPath)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(8)
                        .background(fieldBackground)
                        .cornerRadius(8)

                    Button(action: browseExisting) {
                        Image(systemName: "folder")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(GhostsetButtonStyle())
                }
                .onChange(of: existingPath) { _ in
                    scanForWorktrees()
                }

                // Worktree list
                if !discoveredWorktrees.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Worktrees (\(discoveredWorktrees.count))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(discoveredWorktrees) { wt in
                                worktreeRow(wt)
                                if wt.id != discoveredWorktrees.last?.id {
                                    Divider().opacity(0.3).padding(.horizontal, 10)
                                }
                            }
                        }
                        .background(fieldBackground)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
                        )
                    }
                } else if !existingPath.isEmpty {
                    Text("No worktrees found — the repository itself will be added")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
        }

        if let error = errorMessage {
            Text(error)
                .font(.system(size: 11))
                .foregroundColor(.red)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()

            Button(action: createProject) {
                Text(mode == .clone ? "Clone" : mode == .existing ? "Add" : "Create")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(!isValid || isCreating)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
    }

    // MARK: - Validation

    private var isValid: Bool {
        switch mode {
        case .clone: return !repoURL.isEmpty
        case .empty: return !repoName.isEmpty
        case .existing: return !existingPath.isEmpty || !selectedWorktrees.isEmpty
        }
    }

    // MARK: - Actions

    private func createProject() {
        isCreating = true
        errorMessage = nil

        Task {
            do {
                if mode == .existing {
                    let paths = selectedWorktrees.isEmpty
                        ? [existingPath]
                        : Array(selectedWorktrees)
                    var lastWorkspace: Workspace?
                    for path in paths {
                        lastWorkspace = try await manager.registerExistingProject(path: path)
                    }
                    dismiss()
                    if let ws = lastWorkspace {
                        onCreated(ws)
                    }
                } else {
                    let repoPath: String
                    switch mode {
                    case .clone:
                        repoPath = try await cloneRepo()
                    case .empty:
                        repoPath = try await createEmptyRepo()
                    case .existing:
                        fatalError("Handled above")
                    }

                    let workspace = try await manager.createWorkspace(
                        repo: repoPath,
                        name: "main",
                        baseBranch: "main"
                    )
                    dismiss()
                    onCreated(workspace)
                }
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }

    private func cloneRepo() async throws -> String {
        let name = repoURL.split(separator: "/").last?
            .replacingOccurrences(of: ".git", with: "") ?? "project"
        let dest = "\(location)/\(name)"
        let url = repoURL

        try FileManager.default.createDirectory(
            atPath: location, withIntermediateDirectories: true
        )

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["clone", url, dest]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        continuation.resume(throwing: NSError(
                            domain: "Ghostset", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to clone repository"]
                        ))
                        return
                    }
                    continuation.resume(returning: dest)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func createEmptyRepo() async throws -> String {
        let dest = "\(location)/\(repoName)"

        try FileManager.default.createDirectory(
            atPath: dest, withIntermediateDirectories: true
        )

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["init", dest]
                process.standardOutput = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: dest)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func browseExisting() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository or worktree"
        if panel.runModal() == .OK, let url = panel.url {
            existingPath = url.path
            scanForWorktrees()
        }
    }

    private func browseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            location = url.path
        }
    }

    // MARK: - Worktree Scanning

    private func scanForWorktrees() {
        let path = existingPath
        guard !path.isEmpty else {
            discoveredWorktrees = []
            selectedWorktrees = []
            return
        }

        let existingPaths = Set(manager.workspaces.map(\.worktreePath))
        let output = NewProjectSheet.runGitWorktreeList(repoPath: path)
        let worktrees = NewProjectSheet.parseWorktreeList(output, existingPaths: existingPaths)

        discoveredWorktrees = worktrees
        selectedWorktrees = Set(worktrees.filter { !$0.alreadyAdded }.map(\.path))
    }

    private static func runGitWorktreeList(repoPath: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repoPath, "worktree", "list", "--porcelain"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func parseWorktreeList(_ output: String, existingPaths: Set<String>) -> [DiscoveredWorktree] {
        guard !output.isEmpty else { return [] }
        let blocks = output.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return blocks.compactMap { block in
            let lines = block.components(separatedBy: "\n")
            var path = ""
            var branch = ""
            var isBare = false

            for line in lines {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("branch refs/heads/") {
                    branch = String(line.dropFirst("branch refs/heads/".count))
                } else if line == "bare" {
                    isBare = true
                } else if line == "detached" {
                    branch = "(detached)"
                }
            }

            guard !path.isEmpty, !isBare else { return nil }

            let name = URL(fileURLWithPath: path).lastPathComponent
            let alreadyAdded = existingPaths.contains(path)

            return DiscoveredWorktree(
                path: path,
                name: name,
                branch: branch,
                alreadyAdded: alreadyAdded
            )
        }
    }

    private func worktreeRow(_ wt: DiscoveredWorktree) -> some View {
        let isSelected = selectedWorktrees.contains(wt.path)
        return Button {
            if wt.alreadyAdded { return }
            if isSelected {
                selectedWorktrees.remove(wt.path)
            } else {
                selectedWorktrees.insert(wt.path)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundColor(wt.alreadyAdded ? .secondary : isSelected ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(wt.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(wt.alreadyAdded ? .secondary : .primary)
                    Text(wt.branch)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if wt.alreadyAdded {
                    Text("added")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(wt.alreadyAdded)
    }

    // MARK: - Helpers

    private var fieldBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.04)
    }
}

// MARK: - Discovered Worktree

struct DiscoveredWorktree: Identifiable {
    let path: String
    let name: String
    let branch: String
    let alreadyAdded: Bool

    var id: String { path }
}

// MARK: - Ghostset Button Style

struct GhostsetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .background(Color.secondary.opacity(configuration.isPressed ? 0.15 : 0.1))
            .cornerRadius(8)
    }
}
