import SwiftUI
import GhosttyKit

/// The main window layout: sidebar + terminal detail.
/// Wraps Ghostty's existing terminal views inside a NavigationSplitView
/// with workspace management. Each workspace gets its own Ghostty terminal
/// surface pointed at a git worktree directory.
struct WorkspaceWindow: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    @State private var selectedWorkspaceID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WorkspaceSidebar(
                manager: ghostty.workspaceManager,
                selectedWorkspaceID: $selectedWorkspaceID
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if selectedWorkspaceID == nil {
                selectedWorkspaceID = ghostty.workspaceManager.workspaces.first?.id
            }
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if let wsID = selectedWorkspaceID,
           let workspace = ghostty.workspaceManager.workspaces.first(where: { $0.id == wsID }) {
            WorkspaceTerminalView(
                workspace: workspace,
                manager: ghostty.workspaceManager
            )
        } else {
            WelcomeView()
        }
    }
}

// MARK: - Workspace Terminal View

/// Wraps a Ghostty terminal surface configured for a specific workspace.
/// Creates a real Ghostty.Terminal pointed at the workspace's worktree directory.
struct WorkspaceTerminalView: View {
    let workspace: Workspace
    @ObservedObject var manager: WorktreeManager
    @EnvironmentObject private var ghostty: Ghostty.App

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider()
            terminalSurface
        }
    }

    // MARK: - Header Bar

    private var workspaceHeader: some View {
        HStack(spacing: 8) {
            // Agent icon + name
            if let agent = workspace.agent {
                Image(systemName: agent.iconName)
                    .foregroundColor(.accentColor)
                Text(agent.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(workspace.name)
                .font(.headline)

            Text(workspace.branch)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)

            Spacer()

            // Status
            Image(systemName: workspace.status.iconName)
                .foregroundColor(statusColor)

            // Actions
            Menu {
                Button("Open in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workspace.worktreePath)
                }
                Button("Open in VS Code") {
                    openInApp("Visual Studio Code", path: workspace.worktreePath)
                }
                Button("Open in Cursor") {
                    openInApp("Cursor", path: workspace.worktreePath)
                }
                Divider()
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(workspace.worktreePath, forType: .string)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Terminal Surface

    /// Real Ghostty terminal, configured for this workspace's worktree.
    /// Uses SurfaceForApp to create a surface with the workspace's working directory,
    /// environment variables, and optional agent auto-launch.
    @ViewBuilder
    private var terminalSurface: some View {
        if let app = ghostty.app {
            Ghostty.SurfaceForApp(app, baseConfig: surfaceConfig) { surfaceView in
                Ghostty.SurfaceWrapper(surfaceView: surfaceView)
            }
        } else {
            Text("Terminal not available")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }

    /// Builds a SurfaceConfiguration pointing at the workspace worktree.
    private var surfaceConfig: Ghostty.SurfaceConfiguration {
        WorkspaceWindowController.surfaceConfiguration(for: workspace)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch workspace.status {
        case .creating: return .secondary
        case .ready: return .blue
        case .running: return .green
        case .stopped: return .gray
        case .error: return .red
        }
    }

    private func openInApp(_ appName: String, path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(fileURLWithPath: "/Applications/\(appName).app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
