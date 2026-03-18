import AppKit
import SwiftUI
import GhosttyKit

/// NSWindowController that hosts the WorkspaceWindow SwiftUI view.
/// This integrates with Ghostty's existing window management system.
///
/// Each WorkspaceWindowController manages one workspace window containing:
/// - A sidebar with workspace list
/// - A detail area with Ghostty terminal surfaces (one per workspace)
class WorkspaceWindowController: NSWindowController, NSWindowDelegate {

    private let ghostty: Ghostty.App

    init(_ ghostty: Ghostty.App) {
        self.ghostty = ghostty

        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Ghostset"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 600, height: 400)
        window.center()

        super.init(window: window)
        window.delegate = self

        // Host the SwiftUI workspace view
        let workspaceView = WorkspaceWindow()
            .environmentObject(ghostty)

        window.contentView = NSHostingView(rootView: workspaceView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Allow the controller to be deallocated when the window closes
    }
}

// MARK: - Terminal Surface Factory

/// Creates Ghostty terminal surfaces configured for specific workspaces.
/// This is the bridge between workspace management and Ghostty's terminal system.
extension WorkspaceWindowController {

    /// Creates a SurfaceConfiguration for a workspace.
    /// The resulting config points the terminal at the worktree directory
    /// and optionally launches an agent via initialInput.
    static func surfaceConfiguration(
        for workspace: Workspace
    ) -> Ghostty.SurfaceConfiguration {
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = workspace.worktreePath

        // Set workspace environment variables
        let env = AgentLauncher.environmentVariables(for: workspace)
        config.environmentVariables = env

        // If an agent is configured, send the launch command as initial input
        if let agent = workspace.agent {
            config.initialInput = AgentLauncher.initialInput(
                for: agent,
                workspace: workspace
            )
        }

        return config
    }
}
