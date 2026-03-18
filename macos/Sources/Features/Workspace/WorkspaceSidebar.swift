import SwiftUI

/// The left sidebar showing all active workspaces.
/// Toggle with Cmd+B (matching Superset's shortcut).
struct WorkspaceSidebar: View {
    @ObservedObject var manager: WorktreeManager
    @Binding var selectedWorkspaceID: UUID?
    @State private var showingNewSheet = false
    @State private var workspaceToDelete: Workspace?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            workspaceList
        }
        .frame(minWidth: 200)
        .sheet(isPresented: $showingNewSheet) {
            NewWorkspaceSheet(manager: manager) { workspace in
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
                Text("This will remove the worktree at \(ws.worktreePath). The branch '\(ws.branch)' will be kept.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Workspaces")
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
            Button(action: { showingNewSheet = true }) {
                Image(systemName: "plus")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .help("New Workspace")
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(manager.isCreating)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Workspace List

    private var workspaceList: some View {
        List(selection: $selectedWorkspaceID) {
            if manager.workspaces.isEmpty {
                emptyState
            } else {
                ForEach(manager.workspaces) { workspace in
                    WorkspaceRow(workspace: workspace)
                        .tag(workspace.id)
                        .contextMenu {
                            contextMenu(for: workspace)
                        }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No Workspaces")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Create a workspace to start running agents in parallel.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for workspace: Workspace) -> some View {
        Button("Open in Terminal") {
            selectedWorkspaceID = workspace.id
        }

        Button("Open in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workspace.worktreePath)
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
