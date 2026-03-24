import SwiftUI

struct WorkspaceSidebar: View {
    @ObservedObject var manager: WorktreeManager
    @Binding var selectedWorkspaceID: UUID?
    var activeTabGroup: WorkspaceTabGroup?

    @State private var showingNewWorkspace = false
    @State private var workspaceToDelete: Workspace?
    @State private var deleteFromDisk = false
    @State private var searchText = ""
    @State private var showingSearch = false
    @State private var selectedTag: String?
    @State private var showingNewTag = false
    @State private var newTagName = ""
    @State private var newTagColor = "blue"
    @State private var showingGitPanel = false
    @State private var showingDiffView = false
    @State private var showingTemplates = false
    @State private var showingEnvironments = false
    @State private var settingsWorkspace: Workspace?
    @State private var sortOrder: WorkspaceSortOrder = .manual
    @State private var workspaceFilter: WorkspaceFilter = .active
    @State private var renamingWorkspace: Workspace?
    @State private var renameText = ""
    @State private var deleteError: String?
    @State private var variablePromptTemplate: WorkspaceTemplate?
    @State private var variablePromptWorkspace: Workspace?
    @State private var variablePromptIsNewWorkspace = false
    @State private var pendingNewWorkspace: Workspace?
    @State private var confirmApplyTemplate: WorkspaceTemplate?
    @State private var confirmApplyWorkspace: Workspace?

    var body: some View {
        VStack(spacing: 0) {
            header
            if showingSearch {
                searchBar
                tagBar
                Picker("Filter", selection: $workspaceFilter) {
                    ForEach(WorkspaceFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }
            Divider().opacity(0.4).padding(.top, 4).padding(.bottom, 6)
            workspaceList

            if let ws = selectedWorkspace, showingGitPanel {
                Divider().opacity(0.3)
                GitStatusPanel(workspace: ws)
            }
        }
        .frame(minWidth: 220)
        .onChange(of: selectedWorkspaceID) { newID in
            if let id = newID {
                manager.notifier.markRead(workspaceID: id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.refreshStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ghostset.togglePin"))) { notification in
            guard let wsID = notification.object as? UUID,
                  let ws = manager.workspaces.first(where: { $0.id == wsID }) else { return }
            manager.togglePin(ws)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ghostset.toggleArchive"))) { notification in
            guard let wsID = notification.object as? UUID,
                  let ws = manager.workspaces.first(where: { $0.id == wsID }) else { return }
            manager.toggleArchive(ws)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ghostset.showDiffView"))) { _ in
            showingDiffView = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ghostset.showTemplates"))) { _ in
            showingTemplates = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ghostset.toggleGitPanel"))) { _ in
            showingGitPanel.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ghostset.toggleSearch"))) { _ in
            withAnimation(.easeInOut(duration: 0.15)) { showingSearch.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ghostset.sortWorkspaces"))) { notification in
            if let sort = notification.userInfo?["sort"] as? String {
                switch sort {
                case "name": sortOrder = .name
                case "dateCreated": sortOrder = .dateCreated
                default: sortOrder = .manual
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ghostset.filterWorkspaces"))) { notification in
            if let filter = notification.userInfo?["filter"] as? String {
                switch filter {
                case "active": workspaceFilter = .active
                case "archived": workspaceFilter = .archived
                default: workspaceFilter = .all
                }
            }
        }
        .sheet(isPresented: $showingNewWorkspace) {
            NewWorkspaceSheet(manager: manager) { workspace, template in
                selectedWorkspaceID = workspace.id

                if let template {
                    if !template.variables.isEmpty {
                        // Prompt user for variable values before applying
                        pendingNewWorkspace = workspace
                        variablePromptIsNewWorkspace = true
                        variablePromptWorkspace = nil
                        variablePromptTemplate = template
                    } else {
                        applyTemplateForNewWorkspace(template, workspace: workspace, resolvedVariables: [:])
                    }
                }
            }
        }
        .sheet(isPresented: $showingDiffView) {
            WorkspaceDiffView(manager: manager)
        }
        .sheet(isPresented: $showingTemplates) {
            TemplateManagerView(manager: manager)
        }
        .sheet(isPresented: $showingEnvironments) {
            EnvironmentManagerView(manager: manager)
        }
        .sheet(
            isPresented: .init(
                get: { variablePromptTemplate != nil },
                set: { if !$0 { variablePromptTemplate = nil; variablePromptWorkspace = nil; pendingNewWorkspace = nil } }
            )
        ) {
            if let template = variablePromptTemplate {
                TemplateVariablePrompt(
                    variables: template.variables,
                    onApply: { resolvedValues in
                        if variablePromptIsNewWorkspace {
                            applyTemplateForNewWorkspace(template, workspace: pendingNewWorkspace, resolvedVariables: resolvedValues)
                        } else if let workspace = variablePromptWorkspace {
                            applyTemplateToExisting(template, workspace: workspace, resolvedVariables: resolvedValues)
                        }
                        variablePromptTemplate = nil
                        variablePromptWorkspace = nil
                        pendingNewWorkspace = nil
                    },
                    onCancel: {
                        variablePromptTemplate = nil
                        variablePromptWorkspace = nil
                        pendingNewWorkspace = nil
                    }
                )
            }
        }
        .popover(
            isPresented: .init(
                get: { settingsWorkspace != nil },
                set: { if !$0 { settingsWorkspace = nil } }
            )
        ) {
            if let ws = settingsWorkspace {
                WorkspaceSettingsPopover(manager: manager, workspace: ws)
            }
        }
        .alert(
            deleteFromDisk ? "Delete Worktree?" : "Remove Workspace?",
            isPresented: .init(
                get: { workspaceToDelete != nil },
                set: { if !$0 { workspaceToDelete = nil } }
            )
        ) {
            deleteAlert
        } message: {
            if let ws = workspaceToDelete {
                if deleteFromDisk {
                    Text("This will delete the worktree and files at \(ws.worktreePath). This cannot be undone.")
                } else {
                    Text("This will stop tracking the workspace. Files at \(ws.worktreePath) will be kept.")
                }
            }
        }
        .alert("Delete Failed", isPresented: .init(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            if let error = deleteError {
                Text(error)
            }
        }
        .alert(
            "Apply Template?",
            isPresented: .init(
                get: { confirmApplyTemplate != nil && confirmApplyWorkspace != nil },
                set: { if !$0 { confirmApplyTemplate = nil; confirmApplyWorkspace = nil } }
            )
        ) {
            Button("Apply", role: .destructive) {
                guard let template = confirmApplyTemplate, let workspace = confirmApplyWorkspace else { return }
                confirmApplyTemplate = nil
                confirmApplyWorkspace = nil
                if !template.variables.isEmpty {
                    variablePromptIsNewWorkspace = false
                    variablePromptWorkspace = workspace
                    variablePromptTemplate = template
                } else {
                    selectedWorkspaceID = workspace.id
                    applyTemplateToExisting(template, workspace: workspace, resolvedVariables: [:])
                }
            }
            Button("Cancel", role: .cancel) {
                confirmApplyTemplate = nil
                confirmApplyWorkspace = nil
            }
        } message: {
            if let template = confirmApplyTemplate, let workspace = confirmApplyWorkspace {
                Text("Apply template '\(template.name)'? This will replace all current tabs in '\(workspace.name)'.")
            }
        }
    }

    // MARK: - Filtered Workspaces

    private var filteredWorkspaces: [Workspace] {
        let filtered = manager.workspaces.filter { ws in
            let matchesArchive = workspaceFilter == .all ||
                (workspaceFilter == .active && !ws.isArchived) ||
                (workspaceFilter == .archived && ws.isArchived)
            guard matchesArchive else { return false }

            let matchesTag = selectedTag.map { ws.tags.contains($0) } ?? true
            guard matchesTag else { return false }

            guard !searchText.isEmpty else { return true }
            let scores: [Int] = [
                FuzzyMatch.score(query: searchText, target: ws.name) ?? 0,
                FuzzyMatch.score(query: searchText, target: ws.branch) ?? 0,
                ws.tags.compactMap { FuzzyMatch.score(query: searchText, target: $0) }.max() ?? 0
            ]
            return (scores.max() ?? 0) > 0
        }
        return filtered.sorted { (lhs: Workspace, rhs: Workspace) -> Bool in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            switch sortOrder {
            case .manual:
                return lhs.sortOrder < rhs.sortOrder
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .dateCreated:
                return lhs.createdAt > rhs.createdAt
            case .status:
                return lhs.status.displayLabel < rhs.status.displayLabel
            case .changeCount:
                // TODO: Sort by actual change count once stats are propagated from WorkspaceRow
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private var selectedWorkspace: Workspace? {
        guard let id = selectedWorkspaceID else { return nil }
        return manager.workspaces.first { $0.id == id }
    }

    private var allTags: [String] {
        Array(Set(manager.workspaces.flatMap(\.tags))).sorted()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Workspaces")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingSearch.toggle()
                    if !showingSearch {
                        searchText = ""
                        selectedTag = nil
                        workspaceFilter = .active
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(showingSearch ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            sortMenuButton
            Button {
                showingGitPanel.toggle()
            } label: {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(showingGitPanel ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle git changes")
            addMenu
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .popover(isPresented: $showingNewTag) {
            newTagPopover
        }
    }

    private var sortMenuButton: some View {
        Menu {
            ForEach(WorkspaceSortOrder.allCases, id: \.rawValue) { order in
                Button {
                    sortOrder = order
                } label: {
                    HStack {
                        Text(order.rawValue)
                        if sortOrder == order {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 10))
                .foregroundStyle(sortOrder == .manual ? .secondary : .primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort workspaces")
    }

    private var addMenu: some View {
        Menu {
            Button {
                showingNewWorkspace = true
            } label: {
                Label("New Workspace", systemImage: "plus.rectangle.on.rectangle")
            }
            Button {
                openExistingProject()
            } label: {
                Label("Open Project", systemImage: "folder")
            }
            Divider()
            Button {
                newTagName = ""
                newTagColor = "blue"
                showingNewTag = true
            } label: {
                Label("New Tag", systemImage: "tag")
            }
            Button {
                showingTemplates = true
            } label: {
                Label("Manage Templates", systemImage: "doc.on.doc")
            }
            Button {
                showingEnvironments = true
            } label: {
                Label("Environments", systemImage: "server.rack")
            }
            Divider()
            Button {
                showingDiffView = true
            } label: {
                Label("Compare All Workspaces", systemImage: "square.split.2x1")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Tag Bar

    @ViewBuilder
    private var tagBar: some View {
        if !allTags.isEmpty {
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        tagBarPill("All", color: .secondary, iconName: nil, count: nil, isSelected: selectedTag == nil) {
                            selectedTag = nil
                        }

                        ForEach(allTags, id: \.self) { tagName in
                            let def = manager.tagDefinition(for: tagName)
                            let count = TagDefinition.usageCount(for: tagName, in: manager.workspaces)
                            tagBarPill(
                                tagName,
                                color: def.color,
                                iconName: def.iconName,
                                count: count > 0 ? count : nil,
                                isSelected: selectedTag == tagName
                            ) {
                                selectedTag = selectedTag == tagName ? nil : tagName
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
    }

    private func tagBarPill(
        _ label: String,
        color: Color,
        iconName: String?,
        count: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let icon = iconName {
                    Image(systemName: icon)
                        .font(.system(size: 8))
                }
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSelected ? color.opacity(0.15) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - New Tag Popover

    private var newTagPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Tag")
                .font(.system(size: 12, weight: .semibold))

            TextField("Tag name", text: $newTagName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 5), spacing: 6) {
                ForEach(TagDefinition.availableColors, id: \.name) { colorOption in
                    colorSwatch(colorOption.name, isChosen: newTagColor == colorOption.name)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    showingNewTag = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Add") {
                    let trimmed = newTagName
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                        .replacingOccurrences(of: " ", with: "-")
                    guard !trimmed.isEmpty else { return }
                    manager.upsertTagDefinition(TagDefinition(name: trimmed, colorName: newTagColor))
                    showingNewTag = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 180)
    }

    // MARK: - Workspace List

    private var workspaceList: some View {
        List(selection: $selectedWorkspaceID) {
            if filteredWorkspaces.isEmpty {
                if manager.workspaces.isEmpty {
                    emptyPlaceholder(icon: "rectangle.stack.badge.plus", message: "No workspaces")
                } else {
                    emptyPlaceholder(icon: "magnifyingglass", message: "No matches")
                }
            } else {
                ForEach(filteredWorkspaces) { workspace in
                    workspaceRowView(for: workspace)
                        .tag(workspace.id)
                        .contextMenu { contextMenu(for: workspace) }
                }
                .onMove { indices, destination in
                    manager.moveWorkspaces(from: indices, to: destination)
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func workspaceRowView(for workspace: Workspace) -> some View {
        if renamingWorkspace?.id == workspace.id {
            renameField(for: workspace)
        } else {
            WorkspaceRow(
                workspace: workspace,
                tagLookup: { manager.tagDefinition(for: $0) },
                templateLookup: { tid in manager.templates.first(where: { $0.id == tid })?.name },
                hasUnread: manager.notifier.unreadWorkspaces.contains(workspace.id)
            )
        }
    }

    private func renameField(for workspace: Workspace) -> some View {
        TextField("Name", text: $renameText, onCommit: {
            commitRename(for: workspace)
        })
        .textFieldStyle(.plain)
        .font(.system(size: 12))
        .onExitCommand {
            renamingWorkspace = nil
        }
    }

    private func commitRename(for workspace: Workspace) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != workspace.name {
            let renamed = workspace.renamed(to: trimmed)
            manager.updateWorkspace(renamed)
        }
        renamingWorkspace = nil
    }

    // MARK: - Empty States

    private func emptyPlaceholder(icon: String, message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tertiary)
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for workspace: Workspace) -> some View {
        Button("Open in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workspace.worktreePath)
        }

        Button("Rename...") {
            renamingWorkspace = workspace
            renameText = workspace.name
        }

        Divider()

        Button(workspace.isPinned ? "Unpin" : "Pin to Top") {
            manager.updateWorkspace(workspace.toggledPin())
        }

        Button(workspace.isArchived ? "Unarchive" : "Archive") {
            manager.updateWorkspace(workspace.toggledArchive())
        }

        Divider()

        Menu("Tags") {
            ForEach(manager.tagDefinitions) { def in
                Button {
                    toggleTag(def.name, on: workspace)
                } label: {
                    HStack {
                        Circle()
                            .fill(def.color)
                            .frame(width: 8, height: 8)
                        Text(def.name)
                        Spacer()
                        if workspace.tags.contains(def.name) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button("Manage Tags...") {
                newTagName = ""
                newTagColor = "blue"
                showingNewTag = true
            }
        }

        Divider()

        Button("Settings...") {
            settingsWorkspace = workspace
        }

        Button("Save as Template") {
            let group = workspace.id == selectedWorkspaceID ? activeTabGroup : nil
            manager.saveAsTemplate(workspace, tabGroup: group)
        }

        if !manager.templates.isEmpty {
            Menu("Apply Template") {
                ForEach(manager.templates) { template in
                    Button {
                        confirmApplyTemplate = template
                        confirmApplyWorkspace = workspace
                    } label: {
                        Label(template.name, systemImage: template.agent?.iconName ?? "terminal")
                    }
                }
            }
        }

        Button("Open in VS Code") {
            openInEditor("Visual Studio Code", path: workspace.worktreePath)
        }
        Button("Open in Cursor") {
            openInEditor("Cursor", path: workspace.worktreePath)
        }

        Divider()

        Button("Remove from Workspace") {
            workspaceToDelete = workspace
            deleteFromDisk = false
        }

        Button("Delete Worktree", role: .destructive) {
            workspaceToDelete = workspace
            deleteFromDisk = true
        }
    }

    // MARK: - Delete Alert

    @ViewBuilder
    private var deleteAlert: some View {
        Button(deleteFromDisk ? "Delete" : "Remove", role: .destructive) {
            guard let ws = workspaceToDelete else { return }
            if deleteFromDisk {
                // Show deleting status immediately
                var deleting = ws
                deleting.status = .deleting
                manager.updateWorkspace(deleting)

                Task {
                    do {
                        try await manager.deleteWorkspace(ws)
                    } catch {
                        deleteError = error.localizedDescription
                    }
                    if selectedWorkspaceID == ws.id { selectedWorkspaceID = manager.workspaces.first?.id }
                }
            } else {
                manager.untrackWorkspace(ws)
                if selectedWorkspaceID == ws.id { selectedWorkspaceID = manager.workspaces.first?.id }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    // MARK: - Tag Management

    private func toggleTag(_ tag: String, on workspace: Workspace) {
        let updated = workspace.togglingTag(tag)
        manager.updateWorkspace(updated)
    }

    // MARK: - Helpers

    private func colorSwatch(_ name: String, isChosen: Bool) -> some View {
        let swatchColor = TagDefinition.swiftUIColor(for: name)
        return Circle()
            .fill(swatchColor)
            .frame(width: 20, height: 20)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: isChosen ? 2 : 0))
            .shadow(color: isChosen ? swatchColor.opacity(0.5) : .clear, radius: 3)
            .onTapGesture { newTagColor = name }
    }

    private func openExistingProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository to open as a workspace"
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let ws = try await manager.registerExistingProject(path: url.path)
                await MainActor.run {
                    selectedWorkspaceID = ws.id
                }
            } catch {
                Ghostty.logger.warning("Failed to open project: \(error)")
            }
        }
    }

    private func openInEditor(_ appName: String, path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleID(for: appName)
            ) ?? URL(fileURLWithPath: "/Applications/\(appName).app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func bundleID(for appName: String) -> String {
        switch appName {
        case "Visual Studio Code": return "com.microsoft.VSCode"
        case "Cursor": return "com.todesktop.230313mzl4w4u92"
        default: return ""
        }
    }

    // MARK: - Template Apply Helpers

    /// Apply a template to an existing workspace, with optional resolved variable values.
    private func applyTemplateToExisting(_ template: WorkspaceTemplate, workspace: Workspace, resolvedVariables: [String: String]) {
        selectedWorkspaceID = workspace.id

        let resolvedCreate = resolvedVariables.isEmpty
            ? template.onCreateCommand
            : template.onCreateCommand.map { TemplateVariableSubstitution.substitute($0, variables: resolvedVariables) }
        let resolvedDestroy = resolvedVariables.isEmpty
            ? template.onDestroyCommand
            : template.onDestroyCommand.map { TemplateVariableSubstitution.substitute($0, variables: resolvedVariables) }

        var updated = workspace
        updated.onCreateCommand = resolvedCreate
        updated.onDestroyCommand = resolvedDestroy
        updated.templateID = template.id
        manager.updateWorkspace(updated)

        if let cmd = resolvedCreate, !cmd.isEmpty {
            manager.runLifecycleCommand(cmd, in: workspace.worktreePath)
        }

        NotificationCenter.default.post(
            name: Notification.Name("ghostset.applyTemplate"),
            object: nil,
            userInfo: [
                "template": template,
                "workspaceID": workspace.id,
                "resolvedVariables": resolvedVariables
            ] as [String: Any]
        )
    }

    /// Apply a template to a newly created workspace, with optional resolved variable values.
    private func applyTemplateForNewWorkspace(_ template: WorkspaceTemplate, workspace: Workspace?, resolvedVariables: [String: String]) {
        guard let workspace else { return }

        let resolvedCreate = resolvedVariables.isEmpty
            ? template.onCreateCommand
            : template.onCreateCommand.map { TemplateVariableSubstitution.substitute($0, variables: resolvedVariables) }
        let resolvedDestroy = resolvedVariables.isEmpty
            ? template.onDestroyCommand
            : template.onDestroyCommand.map { TemplateVariableSubstitution.substitute($0, variables: resolvedVariables) }

        var updated = workspace
        updated.onCreateCommand = resolvedCreate
        updated.onDestroyCommand = resolvedDestroy
        updated.templateID = template.id
        manager.updateWorkspace(updated)

        if let cmd = resolvedCreate, !cmd.isEmpty {
            manager.runLifecycleCommand(cmd, in: workspace.worktreePath)
        }

        if !template.tabs.isEmpty {
            NotificationCenter.default.post(
                name: Notification.Name("ghostset.applyTemplate"),
                object: nil,
                userInfo: [
                    "template": template,
                    "workspaceID": workspace.id,
                    "resolvedVariables": resolvedVariables
                ] as [String: Any]
            )
        }
    }
}
