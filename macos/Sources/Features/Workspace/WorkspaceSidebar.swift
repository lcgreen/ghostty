import SwiftUI

/// The left sidebar showing all active workspaces with search and tag filtering.
struct WorkspaceSidebar: View {
    @ObservedObject var manager: WorktreeManager
    @Binding var selectedWorkspaceID: UUID?

    @State private var showingNewWorkspace = false
    @State private var workspaceToDelete: Workspace?
    @State private var deleteFromDisk = false
    @State private var searchText = ""
    @State private var showingSearch = false
    @State private var selectedTag: String?
    @State private var showingNewTag = false
    @State private var newTagName = ""
    @State private var newTagColor = "blue"

    var body: some View {
        VStack(spacing: 0) {
            header
            if showingSearch {
                searchBar
                tagBar
            }
            Divider().opacity(0.4).padding(.top, 4).padding(.bottom, 6)
            workspaceList
        }
        .frame(minWidth: 220)
        .sheet(isPresented: $showingNewWorkspace) {
            NewWorkspaceSheet(manager: manager) { workspace in
                selectedWorkspaceID = workspace.id
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
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingSearch.toggle()
                    if !showingSearch { searchText = "" }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(showingSearch ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            Menu {
                Button {
                    showingNewWorkspace = true
                } label: {
                    Label("New Workspace", systemImage: "plus.rectangle.on.rectangle")
                }
                Divider()
                Button {
                    newTagName = ""
                    newTagColor = "blue"
                    showingNewTag = true
                } label: {
                    Label("New Tag", systemImage: "tag")
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
        .padding(.top, 6)
        .padding(.bottom, 2)
        .popover(isPresented: $showingNewTag) {
            newTagPopover
        }
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
                        tagBarPill("All", color: .secondary, isSelected: selectedTag == nil) {
                            selectedTag = nil
                        }

                        let displayTags = orderedDisplayTags
                        ForEach(displayTags, id: \.self) { tagName in
                            let def = manager.tagDefinition(for: tagName)
                            tagBarPill(tagName, color: def.color, isSelected: selectedTag == tagName) {
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

    /// Only show tags that are actually applied to workspaces.
    private var orderedDisplayTags: [String] {
        allTags
    }

    private func tagBarPill(_ label: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .medium : .regular))
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

            // Color grid
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 5), spacing: 6) {
                ForEach(TagDefinition.availableColors, id: \.name) { colorOption in
                    let isChosen = newTagColor == colorOption.name
                    Circle()
                        .fill(TagDefinition.swiftUIColor(for: colorOption.name))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white, lineWidth: isChosen ? 2 : 0)
                        )
                        .shadow(color: isChosen ? TagDefinition.swiftUIColor(for: colorOption.name).opacity(0.5) : .clear, radius: 3)
                        .onTapGesture {
                            newTagColor = colorOption.name
                        }
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
                    emptyState
                } else {
                    noResultsState
                }
            } else {
                ForEach(filteredWorkspaces) { workspace in
                    WorkspaceRow(
                        workspace: workspace,
                        tagLookup: { manager.tagDefinition(for: $0) }
                    )
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

        // Tag management with colors
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
        if deleteFromDisk {
            Button("Delete", role: .destructive) {
                if let ws = workspaceToDelete {
                    Task {
                        try? await manager.deleteWorkspace(ws)
                        if selectedWorkspaceID == ws.id {
                            selectedWorkspaceID = manager.workspaces.first?.id
                        }
                    }
                }
            }
        } else {
            Button("Remove", role: .destructive) {
                if let ws = workspaceToDelete {
                    manager.untrackWorkspace(ws)
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
