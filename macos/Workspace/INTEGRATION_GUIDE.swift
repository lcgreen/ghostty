// INTEGRATION_GUIDE.swift
//
// This file documents the minimal changes needed to Ghostty's existing
// Swift code to wire up the workspace system. These are the "seams"
// where Ghostset plugs into Ghostty.
//
// ============================================================================
// CHANGE 1: AppDelegate — Add workspace window creation
// ============================================================================
//
// File: macos/Sources/App/macOS/AppDelegate.swift
//
// In Ghostty, `newWindow` creates a `TerminalController`. We add a parallel
// path for workspace mode:
//
//     // EXISTING (keep):
//     @IBAction func newWindow(_ sender: Any?) {
//         let c = TerminalController(ghostty)
//         c.showWindow(self)
//     }
//
//     // ADD:
//     @IBAction func newWorkspaceWindow(_ sender: Any?) {
//         let controller = WorkspaceWindowController(ghostty)
//         controller.showWindow(self)
//     }
//
// Also add a menu item: File > New Workspace Window (Cmd+Shift+N)
//
// ============================================================================
// CHANGE 2: Ghostty.App — Add WorktreeManager to central state
// ============================================================================
//
// File: macos/Sources/Ghostty/Ghostty.App.swift
//
// Ghostty.App is the central @ObservableObject. Add the workspace manager:
//
//     class App: ObservableObject {
//         // EXISTING:
//         @Published var config: Config
//         // ...
//
//         // ADD:
//         @Published var workspaceManager = WorktreeManager()
//     }
//
// ============================================================================
// CHANGE 3: WorkspaceTerminalView — Use real Ghostty.TerminalView
// ============================================================================
//
// In WorkspaceWindow.swift, replace the `terminalPlaceholder` with:
//
//     import GhosttyKit  // The C library
//
//     struct WorkspaceTerminalView: View {
//         let workspace: Workspace
//         let ghostty: Ghostty.App
//
//         var body: some View {
//             VStack(spacing: 0) {
//                 workspaceHeader
//                 Divider()
//                 // The real Ghostty terminal, pointed at the worktree
//                 Ghostty.TerminalView(
//                     ghostty: ghostty,
//                     baseConfig: surfaceConfig(for: workspace)
//                 )
//             }
//         }
//
//         private func surfaceConfig(for ws: Workspace) -> SurfaceConfiguration {
//             var config = SurfaceConfiguration()
//             config.workingDirectory = ws.worktreePath
//             config.environmentVariables = AgentLauncher.environmentVariables(for: ws)
//             if let agent = ws.agent {
//                 config.initialInput = AgentLauncher.initialInput(for: agent, workspace: ws)
//             }
//             return config
//         }
//     }
//
// ============================================================================
// CHANGE 4: SurfaceConfiguration — Ensure environment variables are passed
// ============================================================================
//
// File: macos/Sources/Ghostty/Surface View/SurfaceView.swift
//
// SurfaceConfiguration already has `environmentVariables: [String: String]`.
// Verify that these are passed through to `ghostty_surface_config_s` in the
// `SurfaceView` initializer. If not, add the bridging:
//
//     // In SurfaceView init, when building ghostty_surface_config_s:
//     for (key, value) in configuration.environmentVariables {
//         ghostty_config_set(config, "env", "\(key)=\(value)")
//     }
//
// ============================================================================
// CHANGE 5: Add keyboard shortcut for sidebar toggle
// ============================================================================
//
// File: macos/Sources/App/macOS/AppDelegate.swift (menu setup)
//
// Add to the View menu:
//     NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebar:),
//                keyEquivalent: "b")  // Cmd+B
//
// ============================================================================
// SUMMARY: Files modified in Ghostty
// ============================================================================
//
// Modified (minimal changes):
//   - AppDelegate.swift            (+15 lines: workspace window action + menu item)
//   - Ghostty.App.swift            (+1 line: WorktreeManager property)
//   - SurfaceView.swift            (+5 lines: env var bridging, if not already there)
//
// Added (new files):
//   - Features/Workspace/WorkspaceModel.swift
//   - Features/Workspace/WorktreeManager.swift
//   - Features/Workspace/WorkspacePersistence.swift
//   - Features/Workspace/WorkspaceSidebar.swift
//   - Features/Workspace/WorkspaceRow.swift
//   - Features/Workspace/WorkspaceWindow.swift
//   - Features/Workspace/NewWorkspaceSheet.swift
//   - Features/Workspace/WelcomeView.swift
//   - Features/Agent/AgentType.swift
//   - Features/Agent/AgentLauncher.swift
//   - Features/Git/GitService.swift
//
// Total: ~3 files modified, ~11 files added
// Lines of existing Ghostty code changed: ~21
