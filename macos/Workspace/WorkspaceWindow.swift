import SwiftUI

/// The main window layout: sidebar + terminal detail.
/// This replaces Ghostty's default single-terminal window when in workspace mode.
///
/// Integration point: In the Ghostty fork, this view wraps the existing
/// `TerminalView` inside a NavigationSplitView. The `TerminalView` is
/// configured with `SurfaceConfiguration.workingDirectory` set to the
/// workspace's worktree path.
struct WorkspaceWindow: View {
    @StateObject private var manager = WorktreeManager()
    @State private var selectedWorkspaceID: UUID?
    @State private var sidebarVisible = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WorkspaceSidebar(
                manager: manager,
                selectedWorkspaceID: $selectedWorkspaceID
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            // Select first workspace if none selected
            if selectedWorkspaceID == nil {
                selectedWorkspaceID = manager.workspaces.first?.id
            }
        }
        // Toggle sidebar with Cmd+B (matching Superset)
        .keyboardShortcut("b", modifiers: .command)
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if let wsID = selectedWorkspaceID,
           let workspace = manager.workspaces.first(where: { $0.id == wsID }) {
            WorkspaceTerminalView(workspace: workspace, manager: manager)
        } else {
            WelcomeView(onNewWorkspace: {
                // Trigger new workspace sheet via sidebar
            })
        }
    }
}

// MARK: - Workspace Terminal View

/// Wraps a Ghostty terminal surface configured for a specific workspace.
/// This is the integration point with Ghostty's existing TerminalView.
///
/// In the actual fork, this would:
/// 1. Create a SurfaceConfiguration with workingDirectory = workspace.worktreePath
/// 2. Optionally set initialInput to the agent launch command
/// 3. Pass environment variables (GHOSTSET_WORKSPACE_NAME, etc.)
/// 4. Embed the existing Ghostty TerminalView
struct WorkspaceTerminalView: View {
    let workspace: Workspace
    @ObservedObject var manager: WorktreeManager

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider()
            terminalPlaceholder
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

    // MARK: - Terminal Placeholder

    /// In the actual Ghostty fork, replace this with:
    ///
    /// ```swift
    /// Ghostty.TerminalView(
    ///     ghostty: ghosttyApp,
    ///     surfaceConfig: surfaceConfig(for: workspace)
    /// )
    /// ```
    private var terminalPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Ghostty Terminal Surface")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("Working directory: \(workspace.worktreePath)")
                .font(.caption)
                .foregroundColor(.secondary)

            if let agent = workspace.agent {
                Text("Agent: \(agent.launchCommand)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("(Replace with Ghostty.TerminalView in fork)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .italic()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Integration Point: Surface Configuration
    //
    // When integrated into the Ghostty fork, create a SurfaceConfiguration like:
    //
    // private func surfaceConfig(for workspace: Workspace) -> SurfaceConfiguration {
    //     var config = SurfaceConfiguration()
    //     config.workingDirectory = workspace.worktreePath
    //     config.environmentVariables = [
    //         "GHOSTSET_WORKSPACE_NAME": workspace.name,
    //         "GHOSTSET_WORKSPACE_PATH": workspace.worktreePath,
    //         "GHOSTSET_REPO_PATH": workspace.repoPath,
    //         "GHOSTSET_BRANCH": workspace.branch,
    //     ]
    //     if let agent = workspace.agent {
    //         config.initialInput = agent.launchCommand + "\n"
    //     }
    //     return config
    // }

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
