import SwiftUI

/// A Cmd+K command palette for quick workspace actions.
struct WorkspaceCommandPalette: View {
    @ObservedObject var manager: WorktreeManager
    @Binding var selectedWorkspaceID: UUID?
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var recentActionIDs: [String] = []
    @FocusState private var isFocused: Bool

    private static let recentsKey = "ghostset.recentPaletteActions"
    private static let maxRecents = 5

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                PaletteTextField(
                    text: $query,
                    onSubmit: { executeSelected() },
                    onArrowUp: { moveSelection(-1) },
                    onArrowDown: { moveSelection(1) },
                    onEscape: { isPresented = false }
                )
                .focused($isFocused)
                .onChange(of: query) { _ in selectedIndex = 0 }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().opacity(0.3)

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedResults, id: \.category) { group in
                            sectionHeader(group.category)
                            ForEach(Array(group.results.enumerated()), id: \.element.id) { _, result in
                                let globalIdx = globalIndex(for: result)
                                resultRow(result, isSelected: globalIdx == selectedIndex)
                                    .id(result.id)
                                    .onTapGesture { execute(result) }
                            }
                        }

                        if filteredResults.isEmpty {
                            Text("No results")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(12)
                        }
                    }
                }
                .frame(maxHeight: 300)
                .onChange(of: selectedIndex) { idx in
                    if let item = filteredResults[safeIndex: idx] {
                        proxy.scrollTo(item.id)
                    }
                }
            }
        }
        .frame(width: 420)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            isFocused = true
            recentActionIDs = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isFocused = true
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    // MARK: - Result Row

    private func resultRow(_ result: PaletteResult, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.icon)
                .font(.system(size: 11))
                .foregroundColor(result.iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let shortcut = result.shortcut {
                Text(shortcut)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: - Results

    private struct ResultGroup {
        let category: String
        let results: [PaletteResult]
    }

    private var filteredResults: [PaletteResult] {
        let all = buildResults()
        if query.isEmpty { return all }
        return all.compactMap { result -> PaletteResult? in
            let titleScore = FuzzyMatch.score(query: query, target: result.title)
            let subtitleScore = result.subtitle.flatMap { FuzzyMatch.score(query: query, target: $0) }
            guard let best = [titleScore, subtitleScore].compactMap({ $0 }).max() else { return nil }
            var scored = result
            scored.score = best
            return scored
        }
        .sorted { $0.score > $1.score }
    }

    private var groupedResults: [ResultGroup] {
        let results = filteredResults
        let recentSet = Set(recentActionIDs)
        let order = query.isEmpty
            ? ["Recent", "Workspaces", "Actions", "Git", "Agents", "Tags"]
            : ["Workspaces", "Actions", "Git", "Agents", "Tags"]
        var groups: [ResultGroup] = []
        if query.isEmpty {
            let recents = results.filter { recentSet.contains($0.id) }
            if !recents.isEmpty { groups.append(ResultGroup(category: "Recent", results: recents)) }
        }
        let excluded = query.isEmpty ? recentSet : []
        for cat in order where cat != "Recent" {
            let items = results.filter { $0.category == cat && !excluded.contains($0.id) }
            if !items.isEmpty { groups.append(ResultGroup(category: cat, results: items)) }
        }
        return groups
    }

    private func globalIndex(for result: PaletteResult) -> Int {
        filteredResults.firstIndex(where: { $0.id == result.id }) ?? -1
    }

    private func buildResults() -> [PaletteResult] {
        var results: [PaletteResult] = []

        // Workspaces
        for ws in manager.workspaces {
            results.append(PaletteResult(
                id: "ws-\(ws.id)",
                title: ws.name,
                subtitle: ws.branch,
                icon: ws.agent?.iconName ?? "terminal",
                iconColor: ws.agent.map { AgentColors.color(for: $0) } ?? .secondary,
                category: "Workspaces",
                action: { selectedWorkspaceID = ws.id; isPresented = false }
            ))
        }

        // Actions
        results.append(PaletteResult(
            id: "action-new", title: "New Workspace",
            subtitle: "Create a new workspace", icon: "plus.rectangle.on.rectangle",
            iconColor: .accentColor, shortcut: "⌘N", category: "Actions",
            action: { isPresented = false; postNotification("newWorkspace") }
        ))

        // Dynamic "Create workspace: ..." result
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let lowerQuery = trimmed.lowercased()
        if lowerQuery.hasPrefix("new ") || lowerQuery.hasPrefix("create ") {
            let wsName = trimmed.replacingOccurrences(
                of: "^(?i)(new|create)\\s+", with: "", options: .regularExpression
            )
            if !wsName.isEmpty {
                results.append(PaletteResult(
                    id: "action-create-dynamic",
                    title: "Create workspace: \(wsName)",
                    subtitle: "Set up a new workspace named '\(wsName)'",
                    icon: "plus.rectangle.on.rectangle",
                    iconColor: .accentColor, category: "Actions",
                    action: {
                        isPresented = false
                        postNotification("newWorkspace", info: ["name": wsName])
                    }
                ))
            }
        }

        // Git commands
        results.append(contentsOf: gitResults())

        // Workspace management actions
        results.append(contentsOf: workspaceManagementResults())

        // View & settings actions
        results.append(contentsOf: viewResults())

        // Agent launchers
        for agent in AgentType.builtIn {
            results.append(PaletteResult(
                id: "agent-\(agent.displayName)",
                title: "Launch \(agent.displayName)",
                subtitle: "Start \(agent.displayName) in current workspace",
                icon: agent.iconName,
                iconColor: AgentColors.color(for: agent),
                category: "Agents",
                action: {
                    isPresented = false
                    NotificationCenter.default.post(
                        name: .ghostsetNewWorkspaceTab,
                        object: nil,
                        userInfo: ["agent": agent]
                    )
                }
            ))
        }

        // Tag filters
        let tags = Array(Set(manager.workspaces.flatMap(\.tags))).sorted()
        for tag in tags {
            let def = manager.tagDefinition(for: tag)
            results.append(PaletteResult(
                id: "tag-\(tag)", title: "Filter: \(tag)",
                subtitle: "Show workspaces tagged '\(tag)'", icon: "tag",
                iconColor: def.color, category: "Tags",
                action: { isPresented = false; postNotification("filterTag", info: ["tag": tag]) }
            ))
        }

        return results
    }

    private func workspaceManagementResults() -> [PaletteResult] {
        var results: [PaletteResult] = []

        // Pin/Unpin current workspace
        if let ws = manager.workspaces.first(where: { $0.id == selectedWorkspaceID }) {
            results.append(PaletteResult(
                id: "ws-pin", title: ws.isPinned ? "Unpin Workspace" : "Pin Workspace",
                subtitle: "Pin '\(ws.name)' to top of sidebar", icon: "pin",
                iconColor: .orange, category: "Actions",
                action: { [manager] in manager.togglePin(ws); isPresented = false }
            ))
            results.append(PaletteResult(
                id: "ws-archive", title: ws.isArchived ? "Unarchive Workspace" : "Archive Workspace",
                subtitle: "Archive '\(ws.name)'", icon: "archivebox",
                iconColor: .purple, category: "Actions",
                action: { [manager] in manager.toggleArchive(ws); isPresented = false }
            ))
            results.append(PaletteResult(
                id: "ws-open-finder", title: "Open in Finder",
                subtitle: ws.worktreePath, icon: "folder",
                iconColor: .blue, category: "Actions",
                action: { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ws.worktreePath); isPresented = false }
            ))
            results.append(PaletteResult(
                id: "ws-open-vscode", title: "Open in VS Code",
                subtitle: ws.worktreePath, icon: "chevron.left.forwardslash.chevron.right",
                iconColor: .blue, category: "Actions",
                action: {
                    let url = URL(fileURLWithPath: ws.worktreePath)
                    NSWorkspace.shared.open(
                        [url],
                        withApplicationAt: NSWorkspace.shared.urlForApplication(
                            withBundleIdentifier: "com.microsoft.VSCode"
                        ) ?? URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                    isPresented = false
                }
            ))
            results.append(PaletteResult(
                id: "ws-open-cursor", title: "Open in Cursor",
                subtitle: ws.worktreePath, icon: "cursorarrow.rays",
                iconColor: .purple, category: "Actions",
                action: {
                    let url = URL(fileURLWithPath: ws.worktreePath)
                    NSWorkspace.shared.open(
                        [url],
                        withApplicationAt: NSWorkspace.shared.urlForApplication(
                            withBundleIdentifier: "com.todesktop.230313mzl4w4u92"
                        ) ?? URL(fileURLWithPath: "/Applications/Cursor.app"),
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                    isPresented = false
                }
            ))
        }

        return results
    }

    private func viewResults() -> [PaletteResult] {
        [
            PaletteResult(
                id: "view-diff", title: "Compare All Workspaces",
                subtitle: "View diff across all workspace branches", icon: "square.split.2x1",
                iconColor: .teal, shortcut: "⌘⇧D", category: "Actions",
                action: { isPresented = false; postNotification("showDiffView") }
            ),
            PaletteResult(
                id: "view-templates", title: "Manage Templates",
                subtitle: "Create, edit, and organize workspace templates", icon: "doc.on.doc",
                iconColor: .indigo, category: "Actions",
                action: { isPresented = false; postNotification("showTemplates") }
            ),
            PaletteResult(
                id: "view-git", title: "Toggle Git Panel",
                subtitle: "Show/hide the git changes panel", icon: "arrow.triangle.branch",
                iconColor: .orange, category: "Actions",
                action: { isPresented = false; postNotification("toggleGitPanel") }
            ),
            PaletteResult(
                id: "view-search", title: "Toggle Search",
                subtitle: "Show/hide the search and filter bar", icon: "magnifyingglass",
                iconColor: .secondary, shortcut: "⌘F", category: "Actions",
                action: { isPresented = false; postNotification("toggleSearch") }
            ),
            PaletteResult(
                id: "sort-name", title: "Sort by Name",
                subtitle: "Sort workspaces alphabetically", icon: "textformat.abc",
                iconColor: .secondary, category: "Actions",
                action: { isPresented = false; postNotification("sortWorkspaces", info: ["sort": "name"]) }
            ),
            PaletteResult(
                id: "sort-date", title: "Sort by Date Created",
                subtitle: "Sort workspaces by creation date", icon: "calendar",
                iconColor: .secondary, category: "Actions",
                action: { isPresented = false; postNotification("sortWorkspaces", info: ["sort": "dateCreated"]) }
            ),
            PaletteResult(
                id: "filter-active", title: "Show Active Workspaces",
                subtitle: "Filter to only active workspaces", icon: "tray.full",
                iconColor: .green, category: "Actions",
                action: { isPresented = false; postNotification("filterWorkspaces", info: ["filter": "active"]) }
            ),
            PaletteResult(
                id: "filter-archived", title: "Show Archived Workspaces",
                subtitle: "Filter to only archived workspaces", icon: "archivebox",
                iconColor: .secondary, category: "Actions",
                action: { isPresented = false; postNotification("filterWorkspaces", info: ["filter": "archived"]) }
            ),
        ]
    }

    private func gitResults() -> [PaletteResult] {
        let gitActions: [(id: String, title: String, icon: String, note: String)] = [
            ("git-commit", "Git: Commit", "checkmark.circle", "gitCommit"),
            ("git-push",   "Git: Push",   "arrow.up.circle", "gitPush"),
            ("git-pull",   "Git: Pull",   "arrow.down.circle", "gitPull"),
            ("git-stash",  "Git: Stash",  "tray.and.arrow.down", "gitStash"),
        ]
        return gitActions.map { item in
            PaletteResult(
                id: item.id, title: item.title,
                subtitle: nil, icon: item.icon,
                iconColor: .orange, category: "Git",
                action: { isPresented = false; postNotification(item.note) }
            )
        }
    }

    // MARK: - Navigation

    private func moveSelection(_ delta: Int) {
        let count = filteredResults.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func executeSelected() {
        guard let result = filteredResults[safeIndex: selectedIndex] else { return }
        execute(result)
    }

    private func execute(_ result: PaletteResult) { trackRecent(result.id); result.action() }

    private func trackRecent(_ id: String) {
        var recents = recentActionIDs.filter { $0 != id }
        recents.insert(id, at: 0)
        if recents.count > Self.maxRecents { recents = Array(recents.prefix(Self.maxRecents)) }
        recentActionIDs = recents
        UserDefaults.standard.set(recents, forKey: Self.recentsKey)
    }

    private func postNotification(_ name: String, info: [String: Any]? = nil) {
        NotificationCenter.default.post(
            name: Notification.Name("ghostset.\(name)"), object: nil, userInfo: info
        )
    }
}

// MARK: - Palette Result

struct PaletteResult {
    let id: String
    let title: String
    var subtitle: String?
    let icon: String
    var iconColor: Color = .secondary
    var shortcut: String?
    var category: String = "Actions"
    var score: Int = 0
    let action: () -> Void
}

// MARK: - Palette Text Field (handles arrow keys)

struct PaletteTextField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onArrowUp: () -> Void
    var onArrowDown: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Search workspaces, actions..."
        field.isBordered = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PaletteTextField

        init(_ parent: PaletteTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.moveUp(_:)):       parent.onArrowUp(); return true
            case #selector(NSResponder.moveDown(_:)):     parent.onArrowDown(); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onEscape(); return true
            case #selector(NSResponder.insertNewline(_:)):   parent.onSubmit(); return true
            default: return false
            }
        }
    }
}

// MARK: - Safe Array Access (Workspace)

extension RandomAccessCollection {
    subscript(safeIndex index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
