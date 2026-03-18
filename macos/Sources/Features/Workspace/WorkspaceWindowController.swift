import AppKit
import SwiftUI
import GhosttyKit

extension Notification.Name {
    static let ghostsetSaveSession = Notification.Name("com.ghostset.saveSession")
}

/// NSWindowController that hosts the WorkspaceWindow SwiftUI view.
/// This integrates with Ghostty's existing window management system.
///
/// Each WorkspaceWindowController manages one workspace window containing:
/// - A sidebar with workspace list
/// - A detail area with Ghostty terminal surfaces (one per workspace)
class WorkspaceWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {

    /// Strong references to keep controllers alive while their windows are open.
    /// NSWindow.windowController is weak, so without this the controller would
    /// be deallocated immediately after creation.
    private static var activeControllers: Set<WorkspaceWindowController> = []

    /// All workspace window controllers currently open.
    static var all: [WorkspaceWindowController] {
        Array(activeControllers)
    }

    /// Whether any workspace windows exist (visible or not).
    static var hasWindows: Bool {
        !activeControllers.isEmpty
    }

    private let ghostty: Ghostty.App

    /// The workspace ID this tab was opened with (nil = blank terminal).
    var selectedWorkspaceID: UUID?

    /// Persisted split layout to restore (nil = fresh terminal).
    private(set) var initialSplitLayout: SplitLayout?

    /// Agent to auto-launch in this tab (nil = plain shell).
    private(set) var initialAgent: AgentType?

    /// Agent session ID for resume (e.g. Claude session ID).
    var agentSessionID: String?

    init(
        _ ghostty: Ghostty.App,
        workspaceID: UUID? = nil,
        splitLayout: SplitLayout? = nil,
        title: String? = nil,
        agent: AgentType? = nil,
        agentSessionID: String? = nil
    ) {
        self.ghostty = ghostty
        self.selectedWorkspaceID = workspaceID
        self.initialSplitLayout = splitLayout
        self.titleOverride = title
        self.initialAgent = agent
        self.agentSessionID = agentSessionID

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "👻"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.minSize = NSSize(width: 600, height: 400)

        // Enable native macOS tab bar
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "com.mitchellh.ghostty.workspace"

        super.init(window: window)
        window.delegate = self

        // Host the SwiftUI workspace view
        let workspaceView = WorkspaceWindow(
            initialWorkspaceID: workspaceID,
            initialSplitLayout: splitLayout,
            initialAgent: agent,
            agentSessionID: agentSessionID
        )
        .environmentObject(ghostty)

        window.contentView = NSHostingView(rootView: workspaceView)
        window.center()

        if let title {
            window.title = title
        }

        // Retain self so the controller lives as long as the window
        Self.activeControllers.insert(self)

        // Listen for Ghostty core notifications
        NotificationCenter.default.addObserver(
            self, selector: #selector(onGhosttyNewTab(_:)),
            name: Ghostty.Notification.ghosttyNewTab, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(onGhosttyCommandPalette(_:)),
            name: .ghosttyCommandPaletteDidToggle, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Intercept Ghostty's new_tab action for surfaces in this workspace window.
    /// If the surface belongs to our window, create a workspace tab instead of a terminal window.
    @objc private func onGhosttyCommandPalette(_ notification: Notification) {
        guard let surface = notification.object as? Ghostty.SurfaceView else { return }
        guard let surfaceWindow = surface.window, surfaceWindow == self.window else { return }
        toggleCommandPalette(nil)
    }

    @objc private func onGhosttyNewTab(_ notification: Notification) {
        guard let surface = notification.object as? Ghostty.SurfaceView else { return }
        guard let surfaceWindow = surface.window, surfaceWindow == self.window else { return }
        newWindowForTab(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Tab Title

    /// Custom title override set by the user.
    private(set) var titleOverride: String?

    /// Reference to the active terminal view model (set by the SwiftUI view).
    /// Used to capture split layout for persistence.
    weak var terminalViewModel: WorkspaceTerminalViewModel?

    @IBAction func changeTabTitle(_ sender: Any) {
        guard let window else { return }

        let alert = NSAlert()
        alert.messageText = "Change Tab Title"
        alert.informativeText = "Leave blank to restore the default."
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        textField.stringValue = titleOverride ?? window.title
        alert.accessoryView = textField

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        alert.window.initialFirstResponder = textField

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            guard response == .alertFirstButtonReturn else { return }

            let newTitle = textField.stringValue
            if newTitle.isEmpty {
                self.titleOverride = nil
                self.window?.title = "👻"
            } else {
                self.titleOverride = newTitle
                self.window?.title = newTitle
            }
        }
    }

    // MARK: - Command Palette

    @IBAction func toggleCommandPalette(_ sender: Any?) {
        // Try the registered view model first, fall back to finding it
        if let vm = terminalViewModel {
            vm.commandPaletteIsShowing.toggle()
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleCommandPalette(_:)) {
            return terminalViewModel != nil
        }
        if menuItem.action == #selector(changeTabTitle(_:)) {
            return true
        }
        if menuItem.action == #selector(newTab(_:)) {
            return true
        }
        return true
    }

    // MARK: - New Tab

    /// Intercept the menu bar's Cmd+T action via the responder chain.
    /// This fires before AppDelegate.newTab because window controllers
    /// are higher in the responder chain than the app delegate.
    @IBAction func newTab(_ sender: Any?) {
        newWindowForTab(nil)
    }

    /// Called by macOS when the user clicks "+" in the tab bar.
    /// New tabs inherit the current tab's workspace selection.
    override func newWindowForTab(_ sender: Any?) {
        let newController = WorkspaceWindowController(
            ghostty,
            workspaceID: selectedWorkspaceID
        )
        addAsTab(newController)
    }

    /// Create a new tab with an agent auto-launched.
    func newTabWithAgent(_ agent: AgentType) {
        let newController = WorkspaceWindowController(
            ghostty,
            workspaceID: selectedWorkspaceID,
            title: agent.displayName,
            agent: agent
        )
        addAsTab(newController)
    }

    private func addAsTab(_ newController: WorkspaceWindowController) {
        guard let newWindow = newController.window,
              let existingWindow = self.window else { return }
        existingWindow.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Tear down the SwiftUI hosting view before the window fully closes.
        // This ensures SurfaceViews are deallocated before the Zig core's
        // next tick, preventing dangling pointer crashes.
        window?.contentView = nil

        // Release the strong reference so the controller can be deallocated
        Self.activeControllers.remove(self)
    }

    /// Persist the current set of workspace window tabs.
    static func saveWindowTabState() {
        let tabs = all.map { controller in
            let layout: SplitLayout? = if let vm = controller.terminalViewModel {
                SplitLayout.from(tree: vm.surfaceTree)
            } else {
                nil
            }
            return WindowTabState(
                selectedWorkspaceID: controller.selectedWorkspaceID,
                splitLayout: layout,
                title: controller.titleOverride,
                agent: controller.initialAgent,
                agentSessionID: controller.agentSessionID
            )
        }
        let state = WindowState(tabs: tabs)
        WorkspacePersistence().saveWindowState(state)
    }

    /// Restore workspace window tabs from persistence.
    /// Called once on app launch instead of creating a blank workspace window.
    static func restoreWindowTabs(_ ghostty: Ghostty.App) -> Bool {
        let persistence = WorkspacePersistence()
        guard let state = persistence.loadWindowState(), !state.tabs.isEmpty else {
            return false
        }

        var firstController: WorkspaceWindowController?
        for (index, tab) in state.tabs.enumerated() {
            let controller = WorkspaceWindowController(
                ghostty,
                workspaceID: tab.selectedWorkspaceID,
                splitLayout: tab.splitLayout,
                title: tab.title,
                agent: tab.agent,
                agentSessionID: tab.agentSessionID
            )
            if index == 0 {
                firstController = controller
                controller.showWindow(nil)
            } else if let firstWindow = firstController?.window,
                      let newWindow = controller.window {
                firstWindow.addTabbedWindow(newWindow, ordered: .above)
            }
        }

        // Make the first tab key
        firstController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
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

        // Set workspace environment variables (injected into the process,
        // not printed as export commands in the terminal)
        config.environmentVariables = AgentLauncher.environmentVariables(for: workspace)

        // Agent launching is handled by the presets bar / initialAgent,
        // not baked into the surface configuration.
        return config
    }
}
