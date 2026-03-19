import SwiftUI

/// Unified workspace creation sheet — compact, clean.
struct NewWorkspaceSheet: View {
    @ObservedObject var manager: WorktreeManager
    let onCreated: (Workspace) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var workspaceName = ""
    @State private var taskDescription = ""
    @State private var selectedAgent: AgentType = .claude
    @State private var selectedTags: Set<String> = []
    @State private var repoPath = ""
    @State private var baseBranch = "main"
    @State private var repoBranches: [String] = []
    @State private var repoWorktreeBranches: Set<String> = []
    @State private var branchSearch = ""
    @State private var showingBranchPicker = false
    @State private var showingClone = false
    @State private var showingEmpty = false
    @State private var cloneURL = ""
    @State private var emptyRepoName = ""
    @State private var newRepoLocation = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ghostset/projects").path
    @State private var isAddingRepo = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Name
            nameRow
            Divider().opacity(0.2)

            // Task + agent + tags + submit
            taskSection

            Divider().opacity(0.2)

            // Repo + branch
            bottomBar

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
        .frame(width: 480)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .padding(20)
    }

    // MARK: - Name

    private var nameRow: some View {
        HStack(spacing: 0) {
            TextField("Workspace name", text: $workspaceName)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .onChange(of: workspaceName) { newValue in
                    workspaceName = sanitize(newValue)
                }

            Spacer()

            Text("ghostset/\(workspaceName.isEmpty ? "name" : workspaceName)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.quaternary)
                .padding(.trailing, 12)
        }
    }

    // MARK: - Task Section

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("What do you want to do?", text: $taskDescription, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // Agent + tags + submit — all on one row
            HStack(spacing: 6) {
                agentPicker

                // Inline tag pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(manager.tagDefinitions) { def in
                            tagToggle(def)
                        }
                    }
                }

                Spacer(minLength: 0)

                Button(action: createWorkspace) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(isValid ? .accentColor : Color.secondary.opacity(0.2))
                }
                .buttonStyle(.plain)
                .disabled(!isValid || isCreating)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func tagToggle(_ def: TagDefinition) -> some View {
        let on = selectedTags.contains(def.name)
        return Button {
            if on { selectedTags.remove(def.name) }
            else { selectedTags.insert(def.name) }
        } label: {
            Text(def.name)
                .font(.system(size: 9, weight: on ? .semibold : .regular))
                .foregroundColor(on ? def.color : .secondary.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(on ? def.color.opacity(0.15) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Agent Picker

    private var agentPicker: some View {
        Menu {
            ForEach(AgentType.builtIn, id: \.displayName) { agent in
                Button { selectedAgent = agent } label: {
                    Label(agent.displayName, systemImage: agent.iconName)
                }
            }
            Divider()
            Button { } label: { Label("None", systemImage: "terminal") }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: selectedAgent.iconName).font(.system(size: 9))
                Text(selectedAgent.displayName).font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 7))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(5)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            repoPicker
            branchPicker
            Spacer()
            Text("\u{2318}\u{21A9}")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - Repo Picker

    private var repoPicker: some View {
        Menu {
            let repos = availableRepos
            if !repos.isEmpty {
                ForEach(repos, id: \.self) { repo in
                    Button(repoDisplayName(repo)) {
                        repoPath = repo
                        loadBranches(for: repo)
                    }
                }
                Divider()
            }
            Button("Browse...") { browseForRepo() }
            Button("Clone...") { cloneURL = ""; showingClone = true }
            Button("New Empty...") { emptyRepoName = ""; showingEmpty = true }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(repoPath.isEmpty ? Color.secondary.opacity(0.3) : Color.green)
                    .frame(width: 5, height: 5)
                Text(repoPath.isEmpty ? "repo" : repoDisplayName(repoPath))
                    .font(.system(size: 10))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .popover(isPresented: $showingClone) { clonePopover }
        .popover(isPresented: $showingEmpty) { emptyRepoPopover }
    }

    // MARK: - Clone / Empty Popovers

    private var clonePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clone").font(.system(size: 11, weight: .semibold))
            TextField("https:// or git@...", text: $cloneURL)
                .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
            HStack {
                Spacer()
                Button("Cancel") { showingClone = false }
                    .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 11))
                Button("Clone") { cloneRepo() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(cloneURL.isEmpty || isAddingRepo)
            }
        }
        .padding(10).frame(width: 280)
    }

    private var emptyRepoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Repository").font(.system(size: 11, weight: .semibold))
            TextField("my-project", text: $emptyRepoName)
                .textFieldStyle(.roundedBorder).font(.system(size: 11))
            HStack {
                Spacer()
                Button("Cancel") { showingEmpty = false }
                    .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 11))
                Button("Create") { createEmptyRepo() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(emptyRepoName.isEmpty || isAddingRepo)
            }
        }
        .padding(10).frame(width: 240)
    }

    // MARK: - Branch Picker

    private var branchPicker: some View {
        Button { showingBranchPicker = true } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 8))
                Text(baseBranch).font(.system(size: 10))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 7))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingBranchPicker) { branchPickerPopover }
    }

    private var branchPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 9)).foregroundStyle(.tertiary)
                TextField("Search", text: $branchSearch)
                    .textFieldStyle(.plain).font(.system(size: 11))
                if !branchSearch.isEmpty {
                    Button { branchSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider()

            if repoBranches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(["main", "master", "develop"], id: \.self) { b in branchRow(b, wt: false) }
                }.padding(.vertical, 2)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let wt = filteredWorktreeBranches
                        if !wt.isEmpty {
                            sectionLabel("Worktrees")
                            ForEach(wt, id: \.self) { b in branchRow(b, wt: true) }
                        }
                        let reg = filteredRegularBranches
                        if !reg.isEmpty {
                            sectionLabel("Branches")
                            ForEach(reg, id: \.self) { b in branchRow(b, wt: false) }
                        }
                        if wt.isEmpty && reg.isEmpty {
                            Text("No matches").font(.system(size: 10)).foregroundStyle(.tertiary).padding(8)
                        }
                    }
                }.frame(maxHeight: 220)
            }
        }
        .frame(width: 220)
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
            .textCase(.uppercase).padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
    }

    private func branchRow(_ branch: String, wt: Bool) -> some View {
        let sel = branch == baseBranch
        return Button {
            baseBranch = branch; branchSearch = ""; showingBranchPicker = false
        } label: {
            HStack(spacing: 5) {
                if wt {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 8)).foregroundStyle(.tertiary).frame(width: 10)
                }
                Text(branch).font(.system(size: 11)).lineLimit(1)
                Spacer()
                if sel { Image(systemName: "checkmark").font(.system(size: 9, weight: .medium)).foregroundColor(.accentColor) }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(sel ? Color.accentColor.opacity(0.08) : Color.clear)
        }.buttonStyle(.plain)
    }

    private var filteredWorktreeBranches: [String] {
        let b = repoBranches.filter { repoWorktreeBranches.contains($0) }
        return branchSearch.isEmpty ? b : b.filter { $0.localizedCaseInsensitiveContains(branchSearch) }
    }

    private var filteredRegularBranches: [String] {
        let b = repoBranches.filter { !repoWorktreeBranches.contains($0) }
        return branchSearch.isEmpty ? b : b.filter { $0.localizedCaseInsensitiveContains(branchSearch) }
    }

    // MARK: - Helpers

    private var isValid: Bool { !repoPath.isEmpty }
    private var availableRepos: [String] { Array(Set(manager.workspaces.map(\.repoPath))).sorted() }
    private func repoDisplayName(_ p: String) -> String { URL(fileURLWithPath: p).lastPathComponent }

    private func sanitize(_ input: String) -> String {
        input.lowercased().replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private func browseForRepo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.message = "Select a git repository"
        if panel.runModal() == .OK, let url = panel.url {
            repoPath = url.path; loadBranches(for: url.path)
        }
    }

    // MARK: - Git

    private func loadBranches(for repo: String) {
        repoBranches = []; repoWorktreeBranches = []; branchSearch = ""

        if let output = gitOutput(["git", "-C", repo, "branch", "--format=%(refname:short)"]) {
            repoBranches = output.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.sorted()
        }

        if let output = gitOutput(["git", "-C", repo, "worktree", "list", "--porcelain"]) {
            var wt = Set<String>()
            for line in output.components(separatedBy: "\n") {
                if line.hasPrefix("branch refs/heads/") {
                    wt.insert(String(line.dropFirst("branch refs/heads/".count)))
                }
            }
            repoWorktreeBranches = wt
        }

        if repoBranches.contains("main") { baseBranch = "main" }
        else if repoBranches.contains("master") { baseBranch = "master" }
        else if let f = repoBranches.first { baseBranch = f }
    }

    private func gitOutput(_ args: [String]) -> String? {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args; p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch { return nil }
    }

    private func cloneRepo() {
        isAddingRepo = true; errorMessage = nil
        let url = cloneURL
        let name = url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "project"
        let dest = "\(newRepoLocation)/\(name)"
        Task {
            do {
                try FileManager.default.createDirectory(atPath: newRepoLocation, withIntermediateDirectories: true)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                p.arguments = ["clone", url, dest]
                p.standardOutput = FileHandle.nullDevice; p.standardError = Pipe()
                try p.run(); p.waitUntilExit()
                guard p.terminationStatus == 0 else { errorMessage = "Clone failed"; isAddingRepo = false; return }
                repoPath = dest; loadBranches(for: dest); showingClone = false; isAddingRepo = false
            } catch { errorMessage = error.localizedDescription; isAddingRepo = false }
        }
    }

    private func createEmptyRepo() {
        isAddingRepo = true; errorMessage = nil
        let dest = "\(newRepoLocation)/\(emptyRepoName)"
        Task {
            do {
                try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                p.arguments = ["init", dest]; p.standardOutput = FileHandle.nullDevice
                try p.run(); p.waitUntilExit()
                repoPath = dest; loadBranches(for: dest); showingEmpty = false; isAddingRepo = false
            } catch { errorMessage = error.localizedDescription; isAddingRepo = false }
        }
    }

    // MARK: - Create

    private func createWorkspace() {
        guard isValid else { return }
        isCreating = true; errorMessage = nil
        let name = workspaceName.isEmpty ? sanitize(String(taskDescription.prefix(30))) : workspaceName
        let finalName = name.isEmpty ? "workspace-\(Int.random(in: 1000...9999))" : name
        let tags = Array(selectedTags)
        Task {
            do {
                let task = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                let ws = try await manager.createWorkspace(
                    repo: repoPath, name: finalName, baseBranch: baseBranch,
                    agent: selectedAgent, tags: tags,
                    taskDescription: task.isEmpty ? nil : task
                )
                dismiss(); onCreated(ws)
            } catch { errorMessage = error.localizedDescription; isCreating = false }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews: subviews, containerWidth: proposal.width ?? .infinity).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = layout(subviews: subviews, containerWidth: bounds.width)
        for (i, pos) in r.positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                              proposal: ProposedViewSize(subviews[i].sizeThatFits(.unspecified)))
        }
    }
    private func layout(subviews: Subviews, containerWidth: CGFloat) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []; var x: CGFloat = 0; var y: CGFloat = 0
        var rowH: CGFloat = 0; var maxW: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > containerWidth, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            positions.append(CGPoint(x: x, y: y))
            rowH = max(rowH, s.height); x += s.width + spacing; maxW = max(maxW, x - spacing)
        }
        return (positions, CGSize(width: maxW, height: y + rowH))
    }
}
