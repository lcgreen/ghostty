import SwiftUI

/// The left sidebar showing all active workspaces with search and tag filtering.
struct WorkspaceSidebar: View {
    @ObservedObject var manager: WorktreeManager
    @Binding var selectedWorkspaceID: UUID?

    @State private var showingNewWorkspace = false
    @State private var showingNewProject = false
    @State private var workspaceToDelete: Workspace?
    @State private var searchText = ""
    @State private var selectedTag: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            tagBar
            Divider()
            workspaceList
        }
        .frame(minWidth: 200)
        .sheet(isPresented: $showingNewWorkspace) {
            NewWorkspaceSheet(manager: manager) { workspace in
                selectedWorkspaceID = workspace.id
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet(manager: manager) { workspace in
                selectedWorkspaceID = workspace.id
            }
        }
        .alert(
            "Remove Workspace?",
            isPresented: .init(
                get: { workspaceToDelete != nil },
                set: { if !$0 { workspaceToDelete = nil } }
            )
        ) {
            deleteAlert
        } message: {
            if let ws = workspaceToDelete {
                Text("This will remove the worktree at \(ws.worktreePath).")
            }
        }
    }

    // MARK: - Filtered Workspaces

    private var filteredWorkspaces: [Workspace] {
        manager.workspaces.filter { ws in
            let matchesSearch = searchText.isEmpty ||
                ws.name.localizedCaseInsensitiveContains(searchText) ||
                ws.branch.localizedCaseInsensitiveContains(searchText) ||
                ws.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }

            let matchesTag = selectedTag == nil ||
                ws.tags.contains(selectedTag!)

            return matchesSearch && matchesTag
        }
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
            Menu {
                Button {
                    showingNewWorkspace = true
                } label: {
                    Label("New Workspace", systemImage: "plus.rectangle.on.rectangle")
                }
                Button {
                    showingNewProject = true
                } label: {
                    Label("New Project", systemImage: "folder.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    tagPill("All", isSelected: selectedTag == nil) {
                        selectedTag = nil
                    }
                    ForEach(allTags, id: \.self) { tag in
                        tagPill(tag, isSelected: selectedTag == tag) {
                            selectedTag = selectedTag == tag ? nil : tag
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .padding(.bottom, 4)
        }
    }

    private func tagPill(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Workspace List

    private var workspaceList: some View {
        List(selection: $selectedWorkspaceID) {
            if filteredWorkspaces.isEmpty {
                if manager.workspaces.isEmpty {
                    emptyState
                } else {
                    noResultsState
                }
            } else {
                ForEach(filteredWorkspaces) { workspace in
                    WorkspaceRow(workspace: workspace)
                        .tag(workspace.id)
                        .contextMenu { contextMenu(for: workspace) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No workspaces")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    private var noResultsState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No matches")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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

        Divider()

        // Tag management
        Menu("Tags") {
            ForEach(["feature", "bugfix", "refactor", "experiment", "review"], id: \.self) { tag in
                Button {
                    toggleTag(tag, on: workspace)
                } label: {
                    HStack {
                        Text(tag)
                        if workspace.tags.contains(tag) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()

        Button("Open in VS Code") {
            openInEditor("Visual Studio Code", path: workspace.worktreePath)
        }
        Button("Open in Cursor") {
            openInEditor("Cursor", path: workspace.worktreePath)
        }

        Divider()

        Button("Remove", role: .destructive) {
            workspaceToDelete = workspace
        }
    }

    // MARK: - Delete Alert

    @ViewBuilder
    private var deleteAlert: some View {
        Button("Remove", role: .destructive) {
            if let ws = workspaceToDelete {
                Task {
                    try? await manager.removeWorkspace(ws)
                    if selectedWorkspaceID == ws.id {
                        selectedWorkspaceID = manager.workspaces.first?.id
                    }
                }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    // MARK: - Tag Management

    private func toggleTag(_ tag: String, on workspace: Workspace) {
        guard let idx = manager.workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        var updated = manager.workspaces[idx]
        if updated.tags.contains(tag) {
            updated.tags.removeAll { $0 == tag }
        } else {
            updated.tags.append(tag)
        }
        manager.updateWorkspace(updated)
    }

    // MARK: - Helpers

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
}
