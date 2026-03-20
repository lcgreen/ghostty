import AppKit
import SwiftUI
import GhosttyKit

extension Notification.Name {
    static let ghostsetSaveSession = Notification.Name("com.ghostset.saveSession")
    static let ghostsetNewWorkspaceTab = Notification.Name("com.ghostset.newWorkspaceTab")
}

/// NSWindowController that hosts the WorkspaceWindow SwiftUI view.
/// This integrates with Ghostty's existing window management system.
///
/// Each WorkspaceWindowController manages one workspace window containing:
/// - A sidebar with workspace list
/// - A detail area with Ghostty terminal surfaces (one per workspace)
class WorkspaceWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {

    /// Strong references to keep controllers alive while their windows are open.
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
    private var keyEventMonitor: Any?

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
        window.title = "Ghostty"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.minSize = NSSize(width: 600, height: 400)

        // Custom per-workspace tab bar — native tabs don't support per-workspace tab groups
        window.tabbingMode = .disallowed
        window.tab.title = ""
        // Remove from any existing tab group
        if let tabGroup = window.tabGroup, tabGroup.windows.count > 1 {
            tabGroup.removeWindow(window)
        }
        // Disable macOS window restoration (we handle our own persistence)
        window.isRestorable = false

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

        // Set window title from workspace name or explicit title
        if let title {
            window.title = title
        } else if let workspaceID,
                  let ws = ghostty.workspaceManager.workspaces.first(where: { $0.id == workspaceID }) {
            window.title = ws.name
        }

        // Retain self so the controller lives as long as the window
        Self.activeControllers.insert(self)

        // Intercept keyboard shortcuts for workspace tab management
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.modifierFlags.contains(.command),
                  let window = self.window,
                  event.window == window,
                  let group = self.activeTabGroup else { return event }

            let key = event.charactersIgnoringModifiers ?? ""
            let hasShift = event.modifierFlags.contains(.shift)
            let hasOption = event.modifierFlags.contains(.option)

            // Cmd+1-9: switch tabs (only when multiple tabs)
            if !hasShift && !hasOption && group.tabs.count > 1 {
                if let num = Int(key), num >= 1 && num <= 9 {
                    group.selectTab(at: num - 1)
                    return nil
                }
            }

            // Cmd+W: close tab (when multiple tabs) instead of closing window
            if key == "w" && !hasShift && !hasOption && group.tabs.count > 1 {
                if let activeID = group.activeTabID,
                   let activeTab = group.tabs.first(where: { $0.id == activeID }),
                   !activeTab.isPinned {
                    group.closeTab(id: activeID)
                    // Notify SwiftUI to rebind
                    NotificationCenter.default.post(
                        name: Notification.Name("ghostset.tabClosed"), object: nil
                    )
                }
                return nil
            }

            return event
        }

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
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
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
        newTab(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Tab Title

    /// Custom title override set by the user.
    private(set) var titleOverride: String?

    /// Reference to the active terminal view model (set by the SwiftUI view).
    weak var terminalViewModel: WorkspaceTerminalViewModel?

    /// Reference to the active tab group (set by the SwiftUI view).
    weak var activeTabGroup: WorkspaceTabGroup?

    /// Responds to both menu bar and context menu changeTabTitle: action.
    /// The context menu targets BaseTerminalController.changeTabTitle: but
    /// ObjC dispatch matches by selector name, so this catches it too.
    @objc @IBAction func changeTabTitle(_ sender: Any) {
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
                self.window?.title = "Ghostty"
            } else {
                self.titleOverride = newTitle
                self.window?.title = newTitle
            }

            // Also update the active custom tab's title
            if let group = self.activeTabGroup, let activeID = group.activeTabID,
               let idx = group.tabs.firstIndex(where: { $0.id == activeID }) {
                group.tabs[idx].title = newTitle.isEmpty ? "Shell" : newTitle
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

    // MARK: - New Tab (custom per-workspace tab bar)

    /// Cmd+T — create a new tab in the current workspace.
    @IBAction func newTab(_ sender: Any?) {
        NotificationCenter.default.post(name: .ghostsetNewWorkspaceTab, object: nil)
    }

    /// Launch an agent in a new tab.
    func newTabWithAgent(_ agent: AgentType) {
        NotificationCenter.default.post(
            name: .ghostsetNewWorkspaceTab,
            object: nil,
            userInfo: ["agent": agent]
        )
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        Self.activeControllers.remove(self)
    }

    /// Save all workspace tab groups to session files.
    static func saveWindowTabState() {
        let persistence = WorkspacePersistence()

        // Collect all unique workspace IDs with tab groups
        var saved = Set<UUID>()
        for controller in all {
            guard let wsID = controller.selectedWorkspaceID,
                  let group = controller.activeTabGroup,
                  !saved.contains(wsID) else { continue }
            saved.insert(wsID)

            let tabStates = group.tabs.compactMap { tab -> TabSessionState? in
                guard let layout = SplitLayout.from(tree: tab.viewModel.surfaceTree) else { return nil }
                return TabSessionState(title: tab.title, splitLayout: layout, agent: tab.agent, sessionID: tab.sessionID)
            }
            guard !tabStates.isEmpty else { continue }

            let session = WorkspaceSessionState(
                workspaceID: wsID,
                tabs: tabStates,
                activeTabIndex: group.tabs.firstIndex(where: { $0.id == group.activeTabID }) ?? 0
            )
            persistence.saveSession(session)
        }

        // Also save window-state.json for backward compat
        let tabs = all.map { controller in
            WindowTabState(
                selectedWorkspaceID: controller.selectedWorkspaceID,
                splitLayout: nil, title: controller.titleOverride,
                agent: controller.initialAgent, agentSessionID: controller.agentSessionID
            )
        }
        persistence.saveWindowState(WindowState(tabs: tabs))
    }

    /// Get all controllers for a specific workspace.
    static func controllers(for workspaceID: UUID?) -> [WorkspaceWindowController] {
        all.filter { $0.selectedWorkspaceID == workspaceID }
    }

    /// Restore workspace window tabs from persistence, preserving original order.
    static func restoreWindowTabs(_ ghostty: Ghostty.App) -> Bool {
        let persistence = WorkspacePersistence()
        guard let state = persistence.loadWindowState(), !state.tabs.isEmpty else {
            return false
        }

        var firstController: WorkspaceWindowController?

        // Restore tabs in order (not grouped by workspace — preserves original tab order)
        for (index, tab) in state.tabs.enumerated() {
            let title = tab.title ?? tab.agent?.displayName ?? "Shell"
            let controller = WorkspaceWindowController(
                ghostty,
                workspaceID: tab.selectedWorkspaceID,
                splitLayout: tab.splitLayout,
                title: title,
                agent: tab.agent,
                agentSessionID: tab.agentSessionID
            )

            if let newWindow = controller.window {
                newWindow.title = title
            }

            if index == 0 {
                firstController = controller
                controller.showWindow(nil)
            } else if let firstWindow = firstController?.window,
                      let newWindow = controller.window {
                firstWindow.addTabbedWindow(newWindow, ordered: .above)
            }
        }

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
