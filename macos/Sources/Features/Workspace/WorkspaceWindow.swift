import SwiftUI
import GhosttyKit
import Combine

/// The main workspace window: sidebar + custom tab bar + terminal.
/// Uses a view model cache so workspace switching is instant.
struct WorkspaceWindow: View {
    var initialWorkspaceID: UUID?
    var initialSplitLayout: SplitLayout?
    var initialAgent: AgentType?
    var agentSessionID: String?

    @EnvironmentObject private var ghostty: Ghostty.App
    @State private var selectedWorkspaceID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var isReady = false
    @State private var showingCommandPalette = false
    @StateObject private var vmCache = WorkspaceViewModelCache()
    @StateObject private var splitDelegate = WorkspaceSplitDelegate()

    var body: some View {
        Group {
            if ghostty.app != nil {
                mainContent
                .onAppear {
                    if selectedWorkspaceID == nil {
                        // Restore from initial ID or auto-select first workspace
                        selectedWorkspaceID = initialWorkspaceID
                            ?? ghostty.workspaceManager.workspaces.first?.id
                    }
                    DispatchQueue.main.async {
                        isReady = true
                        bindActiveViewModel()
                    }
                }
                .onChange(of: selectedWorkspaceID) { newID in
                    saveAllSessions()
                    syncToController(newID)
                    bindActiveViewModel()
                }
                .onReceive(NotificationCenter.default.publisher(for: .ghostsetNewWorkspaceTab)) { notification in
                    let agent = notification.userInfo?["agent"] as? AgentType
                    addNewTab(agent: agent)
                    saveAllSessions()
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ghostset.tabClosed"))) { _ in
                    bindActiveViewModel()
                    saveAllSessions()
                }
                // Auto-save sessions every 30 seconds
                .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                    saveAllSessions()
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ghostset.moveTabToWorkspace"))) { notification in
                    guard let info = notification.userInfo,
                          let targetID = info["targetWorkspaceID"] as? UUID,
                          targetID == selectedWorkspaceID,
                          let app = ghostty.app else { return }
                    let agent = info["agent"] as? AgentType

                    // Switch to the target workspace and create a fresh tab there
                    selectedWorkspaceID = targetID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        addNewTab(agent: agent)
                    }
                }
            } else {
                WelcomeView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ghostsetSaveSession)) { _ in
            saveAllSessions()
        }
        .overlay {
            if showingCommandPalette {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showingCommandPalette = false }
                VStack {
                    WorkspaceCommandPalette(
                        manager: ghostty.workspaceManager,
                        selectedWorkspaceID: $selectedWorkspaceID,
                        isPresented: $showingCommandPalette
                    )
                    .padding(.top, 60)
                    Spacer()
                }
            }
        }
        .background {
            // Cmd+K shortcut to toggle command palette
            Button("") { showingCommandPalette.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
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
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if let group = activeTabGroup {
            WorkspaceDetailContent(
                tabGroup: group,
                splitDelegate: splitDelegate,
                workspace: selectedWorkspace,
                workspaceManager: ghostty.workspaceManager,
                onCloseTab: { tabID in
                    group.closeTab(id: tabID)
                    bindActiveViewModel()
                },
                onNewTab: { addNewTab() },
                onLaunchAgent: { agent in launchAgent(agent) }
            )
        }
    }

    // MARK: - Tab Group

    private var selectedWorkspace: Workspace? {
        guard let id = selectedWorkspaceID else { return nil }
        return ghostty.workspaceManager.workspaces.first { $0.id == id }
    }

    private var activeTabGroup: WorkspaceTabGroup? {
        guard let app = ghostty.app else { return nil }
        let workspace = selectedWorkspace
        let config: Ghostty.SurfaceConfiguration? = workspace.map {
            WorkspaceWindowController.surfaceConfiguration(for: $0)
        }
        return vmCache.tabGroup(for: workspace, app: app, baseConfig: config)
    }

    private func addNewTab(agent: AgentType? = nil) {
        guard let app = ghostty.app else { return }
        let workspace = selectedWorkspace
        let config: Ghostty.SurfaceConfiguration? = workspace.map {
            WorkspaceWindowController.surfaceConfiguration(for: $0)
        }
        _ = vmCache.createTab(
            for: workspace, app: app, baseConfig: config,
            title: agent?.displayName ?? "", agent: agent
        )
        bindActiveViewModel()
    }

    private func bindActiveViewModel() {
        guard let group = activeTabGroup, let vm = group.activeViewModel else { return }
        splitDelegate.viewModel = vm
        splitDelegate.workspaceID = selectedWorkspaceID

        DispatchQueue.main.async { [weak splitDelegate] in
            guard let window = NSApp.keyWindow,
                  let controller = window.windowController as? WorkspaceWindowController else { return }
            controller.terminalViewModel = vm
            controller.activeTabGroup = group

            // Subscribe to the surface's title for tab name updates
            if let surface = vm.surfaceTree.first(where: { _ in true }) {
                splitDelegate?.observeSurfaceTitle(surface, tabGroup: group)
            }
        }
    }

    private func syncToController(_ newID: UUID?) {
        if let window = NSApp.keyWindow,
           let controller = window.windowController as? WorkspaceWindowController {
            controller.selectedWorkspaceID = newID
        }
    }

    private func launchAgent(_ agent: AgentType) {
        addNewTab(agent: agent)
    }

    // MARK: - Session Persistence

    private func saveAllSessions() {
        for (wsID, group) in vmCache.allGroups {
            guard let wsID else { continue }
            // Save ALL tabs for this workspace
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
            ghostty.workspaceManager.saveSession(session)
        }
    }

}

// MARK: - Detail Content (observes tab group changes)

/// Inner view that uses @ObservedObject on the tab group so SwiftUI
/// re-renders when tabs are added/removed/switched.
private struct WorkspaceDetailContent: View {
    @ObservedObject var tabGroup: WorkspaceTabGroup
    let splitDelegate: WorkspaceSplitDelegate
    let workspace: Workspace?
    let workspaceManager: WorktreeManager
    var onCloseTab: (UUID) -> Void
    var onNewTab: () -> Void
    var onLaunchAgent: (AgentType) -> Void
    @EnvironmentObject private var ghostty: Ghostty.App

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — only when 2+ tabs
            if tabGroup.tabs.count > 1 {
                WorkspaceTabBar(
                    tabGroup: tabGroup,
                    onClose: onCloseTab,
                    onNew: onNewTab,
                    workspaces: workspaceManager.workspaces,
                    onMoveToWorkspace: { tabID, wsID in moveTab(tabID, toWorkspace: wsID) },
                    onTearOff: { tabID in tearOffTab(tabID) }
                )
                Divider().opacity(0.3)
            }

            // Terminal for active tab
            if let vm = tabGroup.activeViewModel, !vm.surfaceTree.isEmpty {
                TerminalView(
                    ghostty: ghostty,
                    viewModel: vm,
                    delegate: splitDelegate
                )
                .onReceive(Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()) { _ in
                    tabGroup.syncTabTitlesFromSurfaces()
                }
                .onChange(of: tabGroup.activeTabID) { _ in
                    // Rebind split delegate when switching tabs
                    if let vm = tabGroup.activeViewModel {
                        splitDelegate.viewModel = vm

                        // Restore focus to the last focused surface in this tab
                        if let activeTab = tabGroup.activeTab,
                           let surfaceID = activeTab.lastFocusedSurfaceID,
                           let surface = vm.surfaceTree.first(where: { $0.id == surfaceID }) {
                            vm.focusedSurface = surface
                            // Delay to let SwiftUI finish the view update
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                surface.window?.makeFirstResponder(surface)
                            }
                        } else if let firstSurface = vm.surfaceTree.first(where: { _ in true }) {
                            // No saved focus — focus the first surface
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                firstSurface.window?.makeFirstResponder(firstSurface)
                            }
                        }
                    }
                }
            }

            Divider()

            // Status bar
            statusBar
        }
    }

    /// Move a tab to another workspace — creates a fresh terminal in the target workspace's directory.
    private func moveTab(_ tabID: UUID, toWorkspace targetWSID: UUID) {
        guard let tabIndex = tabGroup.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let tab = tabGroup.tabs[tabIndex]
        let agent = tab.agent

        // Remove from current workspace
        onCloseTab(tabID)

        // Post notification to create a new tab in the target workspace
        NotificationCenter.default.post(
            name: Notification.Name("ghostset.moveTabToWorkspace"),
            object: nil,
            userInfo: [
                "agent": agent as Any,
                "targetWorkspaceID": targetWSID
            ] as [String: Any]
        )
    }

    /// Tear off a tab into a standalone Ghostty terminal window.
    private func tearOffTab(_ tabID: UUID) {
        guard let tabIndex = tabGroup.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let tab = tabGroup.tabs[tabIndex]
        let surfaceTree = tab.viewModel.surfaceTree

        // Remove from workspace tab group
        onCloseTab(tabID)

        // Create a new TerminalController with the surface tree
        let controller = TerminalController(
            ghostty,
            withSurfaceTree: surfaceTree
        )
        controller.showWindow(nil)
    }

    private var statusBar: some View {
        let displayWS = workspace ?? workspaceManager.workspaces.first

        return HStack(spacing: 0) {
            AgentPresetsBar { agent in onLaunchAgent(agent) }
            Spacer(minLength: 4)
            if let ws = displayWS {
                HStack(spacing: 5) {
                    if let agent = ws.agent {
                        Image(systemName: agent.iconName)
                            .font(.system(size: 9))
                            .foregroundColor(.accentColor)
                    }
                    Text(ws.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(ws.branch)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Circle()
                    .fill(statusColor(ws.status))
                    .frame(width: 5, height: 5)
                    .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(.ultraThinMaterial)
    }

    private func statusColor(_ status: WorkspaceStatus) -> Color {
        switch status {
        case .creating: .orange; case .ready: .blue
        case .running: .green; case .stopped: .gray; case .error: .red
        }
    }
}

// MARK: - Split Delegate

final class WorkspaceSplitDelegate: NSObject, ObservableObject, TerminalViewDelegate {
    weak var viewModel: WorkspaceTerminalViewModel?
    var workspaceID: UUID?
    private var titleCancellable: AnyCancellable?

    /// Start observing the focused surface's title and update the active tab.
    func observeSurfaceTitle(_ surface: Ghostty.SurfaceView?, tabGroup: WorkspaceTabGroup?) {
        titleCancellable?.cancel()
        guard let surface, let tabGroup else { return }
        titleCancellable = surface.$title
            .receive(on: DispatchQueue.main)
            .sink { title in
                let displayTitle = title.isEmpty ? "Shell" : title
                tabGroup.updateActiveTabTitle(displayTitle)
            }
    }

    override init() {
        super.init()
        let c = NotificationCenter.default
        c.addObserver(self, selector: #selector(onNewTab(_:)), name: Ghostty.Notification.ghosttyNewTab, object: nil)
        c.addObserver(self, selector: #selector(onNewSplit(_:)), name: Ghostty.Notification.ghosttyNewSplit, object: nil)
        c.addObserver(self, selector: #selector(onEqualize(_:)), name: Ghostty.Notification.didEqualizeSplits, object: nil)
        c.addObserver(self, selector: #selector(onFocusSplit(_:)), name: Ghostty.Notification.ghosttyFocusSplit, object: nil)
        c.addObserver(self, selector: #selector(onZoom(_:)), name: Ghostty.Notification.didToggleSplitZoom, object: nil)
        c.addObserver(self, selector: #selector(onResize(_:)), name: Ghostty.Notification.didResizeSplit, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    func focusedSurfaceDidChange(to: Ghostty.SurfaceView?) {
        guard let s = to, let w = s.window else { return }
        let title = s.title.isEmpty ? "Shell" : s.title

        // Track focused surface on the view model (for tab title sync)
        viewModel?.focusedSurface = s

        // Store on the tab entry — only if the surface belongs to the active tab's tree
        if let vm = viewModel, vm.surfaceTree.contains(s),
           let w = s.window,
           let c = w.windowController as? WorkspaceWindowController,
           let group = c.activeTabGroup,
           let activeID = group.activeTabID,
           let idx = group.tabs.firstIndex(where: { $0.id == activeID }),
           group.tabs[idx].viewModel === vm {
            group.tabs[idx].lastFocusedSurfaceID = s.id
        }

        if let c = w.windowController as? WorkspaceWindowController {
            if c.titleOverride == nil {
                w.title = title
            }
            c.activeTabGroup?.updateActiveTabTitle(title)
            observeSurfaceTitle(s, tabGroup: c.activeTabGroup)
        }
    }

    func pwdDidChange(to: URL?) {
        if let name = to?.lastPathComponent, let vm = viewModel, let s = vm.surfaceTree.first,
           let w = s.window, let c = w.windowController as? WorkspaceWindowController {
            if c.titleOverride == nil { w.title = name }
            // Update tab title from surface title (or pwd as fallback)
            let tabTitle = s.title.isEmpty ? name : s.title
            c.activeTabGroup?.updateActiveTabTitle(tabTitle)
        }
        guard let wid = workspaceID, let pwd = to?.path,
              let ad = NSApplication.shared.delegate as? AppDelegate else { return }
        ad.ghostty.workspaceManager.commandHistory.append(entry: CommandHistoryEntry(
            command: "cd \(pwd)", workingDirectory: pwd, timestamp: Date(), workspaceID: wid))
    }

    func cellSizeDidChange(to: NSSize) {}
    func performAction(_ action: String, on: Ghostty.SurfaceView) {}

    func performSplitAction(_ action: TerminalSplitOperation) {
        guard let vm = viewModel else { return }
        switch action {
        case .resize(let r):
            do { vm.surfaceTree = try vm.surfaceTree.replacing(node: r.node, with: r.node.resizing(to: r.ratio)) }
            catch { Ghostty.logger.warning("resize: \(error)") }
        case .drop(let d):
            let dir: SplitTree<Ghostty.SurfaceView>.NewDirection = switch d.zone {
            case .top: .up; case .bottom: .down; case .left: .left; case .right: .right
            }
            if let src = vm.surfaceTree.root?.node(view: d.payload) {
                let t = vm.surfaceTree.removing(src)
                do { vm.surfaceTree = try t.inserting(view: d.payload, at: d.destination, direction: dir) }
                catch { Ghostty.logger.warning("drop: \(error)") }
            } else {
                do { vm.surfaceTree = try vm.surfaceTree.inserting(view: d.payload, at: d.destination, direction: dir) }
                catch { Ghostty.logger.warning("insert: \(error)") }
            }
        }
    }

    // MARK: - Notifications

    @objc private func onNewTab(_ n: Notification) {
        guard let vm = viewModel, let s = n.object as? Ghostty.SurfaceView, vm.surfaceTree.contains(s) else { return }
        // Post to create a workspace tab (handled by WorkspaceWindow)
        NotificationCenter.default.post(name: .ghostsetNewWorkspaceTab, object: nil)
    }

    @objc private func onNewSplit(_ n: Notification) {
        guard let vm = viewModel, let old = n.object as? Ghostty.SurfaceView else { return }
        guard vm.surfaceTree.root?.node(view: old) != nil else { return }
        let cfg = n.userInfo?[Ghostty.Notification.NewSurfaceConfigKey] as? Ghostty.SurfaceConfiguration
        guard let d = n.userInfo?["direction"] as? ghostty_action_split_direction_e else { return }
        let dir: SplitTree<Ghostty.SurfaceView>.NewDirection
        switch d {
        case GHOSTTY_SPLIT_DIRECTION_RIGHT: dir = .right
        case GHOSTTY_SPLIT_DIRECTION_LEFT: dir = .left
        case GHOSTTY_SPLIT_DIRECTION_DOWN: dir = .down
        case GHOSTTY_SPLIT_DIRECTION_UP: dir = .up
        default: return
        }
        guard let ad = NSApplication.shared.delegate as? AppDelegate, let app = ad.ghostty.app else { return }
        let nv = Ghostty.SurfaceView(app, baseConfig: cfg)
        do { vm.surfaceTree = try vm.surfaceTree.inserting(view: nv, at: old, direction: dir) }
        catch { Ghostty.logger.warning("split: \(error)") }
        DispatchQueue.main.async { Ghostty.moveFocus(to: nv, from: old) }
    }

    @objc private func onEqualize(_ n: Notification) {
        guard let vm = viewModel, let t = n.object as? Ghostty.SurfaceView, vm.surfaceTree.contains(t) else { return }
        vm.surfaceTree = vm.surfaceTree.equalized()
    }

    @objc private func onFocusSplit(_ n: Notification) {
        guard let vm = viewModel, let t = n.object as? Ghostty.SurfaceView else { return }
        guard let node = vm.surfaceTree.root?.node(view: t) else { return }
        guard let d = n.userInfo?[Ghostty.Notification.SplitDirectionKey] as? Ghostty.SplitFocusDirection else { return }
        guard let next = vm.surfaceTree.focusTarget(for: d.toSplitTreeFocusDirection(), from: node) else { return }
        DispatchQueue.main.async { Ghostty.moveFocus(to: next, from: t) }
    }

    @objc private func onZoom(_ n: Notification) {
        guard let vm = viewModel, let t = n.object as? Ghostty.SurfaceView else { return }
        guard let node = vm.surfaceTree.root?.node(view: t) else { return }
        if vm.surfaceTree.zoomed == node {
            vm.surfaceTree = SplitTree(root: vm.surfaceTree.root, zoomed: nil)
        } else {
            guard vm.surfaceTree.isSplit else { return }
            vm.surfaceTree = SplitTree(root: vm.surfaceTree.root, zoomed: node)
        }
        DispatchQueue.main.async { Ghostty.moveFocus(to: t) }
    }

    @objc private func onResize(_ n: Notification) {
        guard let vm = viewModel, let t = n.object as? Ghostty.SurfaceView else { return }
        guard let node = vm.surfaceTree.root?.node(view: t) else { return }
        guard let d = n.userInfo?[Ghostty.Notification.ResizeSplitDirectionKey] as? Ghostty.SplitResizeDirection,
              let amt = n.userInfo?[Ghostty.Notification.ResizeSplitAmountKey] as? UInt16 else { return }
        let sd: SplitTree<Ghostty.SurfaceView>.Spatial.Direction = switch d {
        case .up: .up; case .down: .down; case .left: .left; case .right: .right
        }
        let bounds = CGRect(origin: .zero, size: vm.surfaceTree.viewBounds())
        do { vm.surfaceTree = try vm.surfaceTree.resizing(node: node, by: amt, in: sd, with: bounds) }
        catch { Ghostty.logger.warning("resize: \(error)") }
    }
}
