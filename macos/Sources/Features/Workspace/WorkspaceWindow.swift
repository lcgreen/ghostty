import SwiftUI
import GhosttyKit

/// The main window layout: sidebar + terminal detail.
/// Wraps Ghostty's existing terminal views inside a NavigationSplitView
/// with workspace management. Each workspace gets its own Ghostty terminal
/// surface with full split support.
struct WorkspaceWindow: View {
    /// Pre-selected workspace ID (for restoring tabs from persistence).
    var initialWorkspaceID: UUID?
    /// Pre-loaded split layout (for restoring splits from persistence).
    var initialSplitLayout: SplitLayout?
    /// Agent to auto-launch in this tab.
    var initialAgent: AgentType?
    /// Agent session ID for resume.
    var agentSessionID: String?

    @EnvironmentObject private var ghostty: Ghostty.App
    @State private var selectedWorkspaceID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    /// Deferred so the terminal surface is not created during initial
    /// NavigationSplitView layout passes (which can create-then-destroy
    /// the detail view, leaving the Zig core with a dangling pointer).
    @State private var isReady = false

    var body: some View {
        Group {
            if ghostty.app != nil {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    WorkspaceSidebar(
                        manager: ghostty.workspaceManager,
                        selectedWorkspaceID: $selectedWorkspaceID
                    )
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
                } detail: {
                    if isReady {
                        detailView
                    }
                }
                .navigationSplitViewStyle(.balanced)
                .onAppear {
                    if selectedWorkspaceID == nil, let initialWorkspaceID {
                        selectedWorkspaceID = initialWorkspaceID
                    }
                    DispatchQueue.main.async {
                        isReady = true
                    }
                }
                .onChange(of: selectedWorkspaceID) { newID in
                    // Sync workspace selection back to the window controller
                    // so new tabs inherit the correct workspace
                    if let window = NSApp.keyWindow,
                       let controller = window.windowController as? WorkspaceWindowController {
                        controller.selectedWorkspaceID = newID
                    }
                }
            } else {
                WelcomeView()
            }
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if let wsID = selectedWorkspaceID,
           let workspace = ghostty.workspaceManager.workspaces.first(where: { $0.id == wsID }) {
            WorkspaceTerminalPanel(
                workspace: workspace,
                manager: ghostty.workspaceManager,
                initialSplitLayout: initialSplitLayout,
                initialAgent: initialAgent,
                agentSessionID: agentSessionID
            )
        } else {
            WorkspaceTerminalPanel(
                workspace: nil,
                manager: ghostty.workspaceManager,
                initialSplitLayout: initialSplitLayout,
                initialAgent: initialAgent,
                agentSessionID: agentSessionID
            )
        }
    }
}

// MARK: - Workspace Terminal Panel

/// A terminal panel with full split support, using native macOS tabs.
/// Each native tab is a full workspace window; this view handles one tab's content.
struct WorkspaceTerminalPanel: View {
    let workspace: Workspace?
    @ObservedObject var manager: WorktreeManager
    var initialSplitLayout: SplitLayout?
    var initialAgent: AgentType?
    var agentSessionID: String?
    @EnvironmentObject private var ghostty: Ghostty.App
    @StateObject private var splitDelegate = WorkspaceSplitDelegate()
    @StateObject private var viewModel = WorkspaceTerminalViewModel()

    var body: some View {
        VStack(spacing: 0) {
            terminalContent
            Divider()
            statusBar
        }
        .onAppear {
            if viewModel.surfaceTree.isEmpty, let app = ghostty.app {
                let baseConfig: Ghostty.SurfaceConfiguration? = workspace.map {
                    WorkspaceWindowController.surfaceConfiguration(for: $0)
                }

                var config = baseConfig ?? Ghostty.SurfaceConfiguration()
                let isRestoring = initialSplitLayout != nil

                // Only launch agent on fresh tabs (clicked from presets bar).
                // Restored tabs just open a shell — user can re-launch manually.
                if !isRestoring, let agent = initialAgent {
                    config.initialInput = agent.launchCommand + "\n"
                }

                // Only restore splits when explicitly provided (from persistence).
                // New tabs (Cmd+T, presets bar) always start with a single pane.
                if let layout = initialSplitLayout {
                    viewModel.surfaceTree = layout.toSplitTree(
                        app: app, baseConfig: config
                    )
                } else {
                    viewModel.surfaceTree = SplitTree(
                        view: Ghostty.SurfaceView(app, baseConfig: config)
                    )
                }
            }
            splitDelegate.viewModel = viewModel
            splitDelegate.workspaceID = workspace?.id

            // Register the view model with the window controller for persistence.
            // Deferred so the hosting view is attached to the window.
            DispatchQueue.main.async {
                for window in NSApp.windows {
                    if let controller = window.windowController as? WorkspaceWindowController,
                       controller.terminalViewModel == nil {
                        controller.terminalViewModel = viewModel
                        break
                    }
                }
            }

        }
        .onReceive(NotificationCenter.default.publisher(for: .ghostsetSaveSession)) { _ in
            saveSessionState()
        }
    }

    // MARK: - Session Persistence

    private func saveSessionState() {
        guard let workspace else { return }
        guard let layout = SplitLayout.from(tree: viewModel.surfaceTree) else { return }

        let tab = TabSessionState(title: "Shell", splitLayout: layout)
        let session = WorkspaceSessionState(
            workspaceID: workspace.id,
            tabs: [tab]
        )
        ghostty.workspaceManager.saveSession(session)
    }

    // MARK: - Terminal Content

    @ViewBuilder
    private var terminalContent: some View {
        if !viewModel.surfaceTree.isEmpty {
            TerminalView(
                ghostty: ghostty,
                viewModel: viewModel,
                delegate: splitDelegate
            )
        }
    }

    // MARK: - Status Bar

    /// The workspace to display in the status bar — either the selected one
    /// or the first available from the manager.
    private var displayWorkspace: Workspace? {
        workspace ?? ghostty.workspaceManager.workspaces.first
    }

    private var statusBar: some View {
        HStack(spacing: 0) {
            AgentPresetsBar { agent in
                launchAgent(agent)
            }

            Spacer(minLength: 4)

            if let ws = displayWorkspace {
                workspaceStatusContent(ws)

                statusIndicator(ws.status)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(.ultraThinMaterial)
    }

    private func launchAgent(_ agent: AgentType) {
        // Find the workspace window controller and create a new tab with the agent
        guard let surface = viewModel.surfaceTree.first,
              let window = surface.window,
              let controller = window.windowController as? WorkspaceWindowController else { return }
        controller.newTabWithAgent(agent)
    }

    private func workspaceStatusContent(_ workspace: Workspace) -> some View {
        HStack(spacing: 5) {
            if let agent = workspace.agent {
                Image(systemName: agent.iconName)
                    .font(.system(size: 9))
                    .foregroundColor(.accentColor)
            }

            Text(workspace.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text(workspace.branch)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func statusIndicator(_ status: WorkspaceStatus) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 5, height: 5)
            .padding(.trailing, 2)
    }

    // MARK: - Helpers

    private func statusColor(_ status: WorkspaceStatus) -> Color {
        switch status {
        case .creating: return .orange
        case .ready: return .blue
        case .running: return .green
        case .stopped: return .gray
        case .error: return .red
        }
    }
}

// MARK: - Split Delegate

/// Handles split operations for workspace terminal panels.
/// Observes the same Ghostty notifications as BaseTerminalController to support
/// splits created via menu items and keybindings (which go through the Zig core).
final class WorkspaceSplitDelegate: NSObject, ObservableObject, TerminalViewDelegate {
    /// The view model for the terminal in this panel.
    weak var viewModel: WorkspaceTerminalViewModel?

    /// The workspace ID for command history tracking.
    var workspaceID: UUID?

    /// Tracks previous pwd per surface to detect directory changes.
    private var lastPwd: [ObjectIdentifier: String] = [:]

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(onNewTab(_:)),
                           name: Ghostty.Notification.ghosttyNewTab, object: nil)
        center.addObserver(self, selector: #selector(onNewSplit(_:)),
                           name: Ghostty.Notification.ghosttyNewSplit, object: nil)
        center.addObserver(self, selector: #selector(onEqualizeSplits(_:)),
                           name: Ghostty.Notification.didEqualizeSplits, object: nil)
        center.addObserver(self, selector: #selector(onFocusSplit(_:)),
                           name: Ghostty.Notification.ghosttyFocusSplit, object: nil)
        center.addObserver(self, selector: #selector(onToggleSplitZoom(_:)),
                           name: Ghostty.Notification.didToggleSplitZoom, object: nil)
        center.addObserver(self, selector: #selector(onResizeSplit(_:)),
                           name: Ghostty.Notification.didResizeSplit, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - TerminalViewDelegate

    func focusedSurfaceDidChange(to: Ghostty.SurfaceView?) {
        // Update window title from focused surface's title
        guard let surface = to, let window = surface.window else { return }
        if let controller = window.windowController as? WorkspaceWindowController,
           controller.titleOverride == nil {
            let title = surface.title ?? ""
            window.title = title.isEmpty ? "👻" : title
        }
    }

    /// The title override from the window controller (nil = use surface title).
    private var titleOverride: String? {
        guard let viewModel else { return nil }
        // Check all surfaces' windows for our controller
        for surface in viewModel.surfaceTree {
            if let controller = surface.window?.windowController as? WorkspaceWindowController {
                return controller.titleOverride
            }
        }
        return nil
    }

    func pwdDidChange(to: URL?) {
        // Update window title to show current directory
        if let pwd = to?.lastPathComponent {
            if let viewModel, let surface = viewModel.surfaceTree.first {
                if let window = surface.window,
                   let controller = window.windowController as? WorkspaceWindowController,
                   controller.titleOverride == nil {
                    window.title = pwd
                }
            }
        }

        // Track pwd changes as command history entries
        guard let workspaceID, let pwd = to?.path else { return }
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }

        let history = appDelegate.ghostty.workspaceManager.commandHistory
        let entry = CommandHistoryEntry(
            command: "cd \(pwd)",
            workingDirectory: pwd,
            timestamp: Date(),
            workspaceID: workspaceID
        )
        history.append(entry: entry)
    }

    func cellSizeDidChange(to: NSSize) {}
    func performAction(_ action: String, on: Ghostty.SurfaceView) {}

    func performSplitAction(_ action: TerminalSplitOperation) {
        guard let viewModel else { return }

        switch action {
        case .resize(let resize):
            let resizedNode = resize.node.resizing(to: resize.ratio)
            do {
                viewModel.surfaceTree = try viewModel.surfaceTree.replacing(
                    node: resize.node, with: resizedNode
                )
            } catch {
                Ghostty.logger.warning("workspace split resize failed: \(error)")
            }

        case .drop(let drop):
            let direction: SplitTree<Ghostty.SurfaceView>.NewDirection = switch drop.zone {
            case .top: .up
            case .bottom: .down
            case .left: .left
            case .right: .right
            }

            if let sourceNode = viewModel.surfaceTree.root?.node(view: drop.payload) {
                let treeWithout = viewModel.surfaceTree.removing(sourceNode)
                do {
                    viewModel.surfaceTree = try treeWithout.inserting(
                        view: drop.payload, at: drop.destination, direction: direction
                    )
                } catch {
                    Ghostty.logger.warning("workspace split drop failed: \(error)")
                }
            } else {
                do {
                    viewModel.surfaceTree = try viewModel.surfaceTree.inserting(
                        view: drop.payload, at: drop.destination, direction: direction
                    )
                } catch {
                    Ghostty.logger.warning("workspace split insert failed: \(error)")
                }
            }
        }
    }

    // MARK: - Notification Handlers

    @objc private func onNewTab(_ notification: Notification) {
        guard let viewModel else { return }
        guard let surface = notification.object as? Ghostty.SurfaceView else { return }
        guard viewModel.surfaceTree.contains(surface) else { return }
        guard let window = surface.window,
              let controller = window.windowController as? WorkspaceWindowController else { return }
        controller.newWindowForTab(nil)
    }

    @objc private func onNewSplit(_ notification: Notification) {
        guard let viewModel else { return }
        guard let oldView = notification.object as? Ghostty.SurfaceView else { return }
        guard viewModel.surfaceTree.root?.node(view: oldView) != nil else { return }

        let configAny = notification.userInfo?[Ghostty.Notification.NewSurfaceConfigKey]
        let config = configAny as? Ghostty.SurfaceConfiguration

        guard let directionAny = notification.userInfo?["direction"] else { return }
        guard let direction = directionAny as? ghostty_action_split_direction_e else { return }
        let splitDirection: SplitTree<Ghostty.SurfaceView>.NewDirection
        switch direction {
        case GHOSTTY_SPLIT_DIRECTION_RIGHT: splitDirection = .right
        case GHOSTTY_SPLIT_DIRECTION_LEFT: splitDirection = .left
        case GHOSTTY_SPLIT_DIRECTION_DOWN: splitDirection = .down
        case GHOSTTY_SPLIT_DIRECTION_UP: splitDirection = .up
        default: return
        }

        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate,
              let ghosttyApp = appDelegate.ghostty.app else { return }
        let newView = Ghostty.SurfaceView(ghosttyApp, baseConfig: config)
        do {
            viewModel.surfaceTree = try viewModel.surfaceTree.inserting(
                view: newView, at: oldView, direction: splitDirection
            )
        } catch {
            Ghostty.logger.warning("workspace new split failed: \(error)")
        }

        DispatchQueue.main.async {
            Ghostty.moveFocus(to: newView, from: oldView)
        }
    }

    @objc private func onEqualizeSplits(_ notification: Notification) {
        guard let viewModel else { return }
        guard let target = notification.object as? Ghostty.SurfaceView else { return }
        guard viewModel.surfaceTree.contains(target) else { return }
        viewModel.surfaceTree = viewModel.surfaceTree.equalized()
    }

    @objc private func onFocusSplit(_ notification: Notification) {
        guard let viewModel else { return }
        guard let target = notification.object as? Ghostty.SurfaceView else { return }
        guard let targetNode = viewModel.surfaceTree.root?.node(view: target) else { return }

        guard let directionAny = notification.userInfo?[Ghostty.Notification.SplitDirectionKey] else { return }
        guard let direction = directionAny as? Ghostty.SplitFocusDirection else { return }

        guard let nextSurface = viewModel.surfaceTree.focusTarget(
            for: direction.toSplitTreeFocusDirection(), from: targetNode
        ) else { return }

        DispatchQueue.main.async {
            Ghostty.moveFocus(to: nextSurface, from: target)
        }
    }

    @objc private func onToggleSplitZoom(_ notification: Notification) {
        guard let viewModel else { return }
        guard let target = notification.object as? Ghostty.SurfaceView else { return }
        guard let targetNode = viewModel.surfaceTree.root?.node(view: target) else { return }

        if viewModel.surfaceTree.zoomed == targetNode {
            viewModel.surfaceTree = SplitTree(root: viewModel.surfaceTree.root, zoomed: nil)
        } else {
            guard viewModel.surfaceTree.isSplit else { return }
            viewModel.surfaceTree = SplitTree(root: viewModel.surfaceTree.root, zoomed: targetNode)
        }

        DispatchQueue.main.async {
            Ghostty.moveFocus(to: target)
        }
    }

    @objc private func onResizeSplit(_ notification: Notification) {
        guard let viewModel else { return }
        guard let target = notification.object as? Ghostty.SurfaceView else { return }
        guard let targetNode = viewModel.surfaceTree.root?.node(view: target) else { return }

        guard let directionAny = notification.userInfo?[Ghostty.Notification.ResizeSplitDirectionKey],
              let direction = directionAny as? Ghostty.SplitResizeDirection else { return }
        guard let amountAny = notification.userInfo?[Ghostty.Notification.ResizeSplitAmountKey],
              let amount = amountAny as? UInt16 else { return }

        let spatialDirection: SplitTree<Ghostty.SurfaceView>.Spatial.Direction
        switch direction {
        case .up: spatialDirection = .up
        case .down: spatialDirection = .down
        case .left: spatialDirection = .left
        case .right: spatialDirection = .right
        }

        let bounds = CGRect(origin: .zero, size: viewModel.surfaceTree.viewBounds())
        do {
            viewModel.surfaceTree = try viewModel.surfaceTree.resizing(
                node: targetNode, by: amount, in: spatialDirection, with: bounds
            )
        } catch {
            Ghostty.logger.warning("workspace split resize failed: \(error)")
        }
    }
}
