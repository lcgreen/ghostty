import SwiftUI
import GhosttyKit

/// A single tab within a workspace — has a title and owns a terminal view model.
struct WorkspaceTabEntry: Identifiable {
    let id: UUID
    var title: String
    let viewModel: WorkspaceTerminalViewModel
    var agent: AgentType?
    var sessionID: String?
    var isPinned: Bool = false
    var colorName: String?
    var iconOverride: String?
    /// ID of the last focused surface in this tab (for restoring focus on tab switch).
    var lastFocusedSurfaceID: UUID?

    init(title: String = "", viewModel: WorkspaceTerminalViewModel, agent: AgentType? = nil, sessionID: String? = nil) {
        self.id = UUID()
        self.title = title
        self.viewModel = viewModel
        self.agent = agent
        self.sessionID = sessionID
    }
}

/// Per-workspace tab state — tracks tabs and which is active.
class WorkspaceTabGroup: ObservableObject {
    @Published var tabs: [WorkspaceTabEntry] = []
    @Published var activeTabID: UUID?

    var activeTab: WorkspaceTabEntry? {
        tabs.first { $0.id == activeTabID }
    }

    var activeViewModel: WorkspaceTerminalViewModel? {
        activeTab?.viewModel
    }

    func addTab(_ entry: WorkspaceTabEntry, activate: Bool = true) {
        tabs.append(entry)
        if activate { activeTabID = entry.id }
    }

    func updateActiveTabTitle(_ title: String) {
        guard let id = activeTabID,
              let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        // Don't override agent tab titles
        guard tabs[idx].agent == nil else { return }
        if tabs[idx].title != title {
            tabs[idx].title = title
        }
    }

    /// Sync all tab titles from their focused surface view.
    /// Uses the focused surface (last responder) or falls back to first surface.
    /// Only updates if the surface title has been stable (not changing rapidly).
    private var lastSeenTitles: [UUID: (title: String, since: Date)] = [:]

    func syncTabTitlesFromSurfaces() {
        let now = Date()
        for i in tabs.indices {
            guard tabs[i].agent == nil else { continue }

            // Find the focused surface (first responder) or fall back to first surface
            let surface = tabs[i].viewModel.focusedSurface
                ?? tabs[i].viewModel.surfaceTree.first(where: { _ in true })
            guard let surface else { continue }
            let surfaceTitle = surface.title
            guard !surfaceTitle.isEmpty else { continue }

            let tabID = tabs[i].id
            if let last = lastSeenTitles[tabID], last.title == surfaceTitle {
                if now.timeIntervalSince(last.since) > 0.5 && tabs[i].title != surfaceTitle {
                    tabs[i].title = surfaceTitle
                }
            } else {
                lastSeenTitles[tabID] = (title: surfaceTitle, since: now)
            }
        }
    }

    func selectTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        activeTabID = tabs[index].id
    }

    func togglePin(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].isPinned.toggle()
        // Move pinned tabs to the front
        let pinned = tabs.filter(\.isPinned)
        let unpinned = tabs.filter { !$0.isPinned }
        tabs = pinned + unpinned
    }

    func setTabColor(id: UUID, color: String?) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].colorName = color
    }

    func setTabIcon(id: UUID, icon: String?) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].iconOverride = icon
    }

    func moveTab(id: UUID, toIndex destination: Int) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let dest = min(destination, tabs.count - 1)
        guard sourceIndex != dest else { return }
        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: dest)
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabID == id
        tabs.remove(at: index)
        if wasActive {
            let safeIndex = min(index, max(tabs.count - 1, 0))
            activeTabID = tabs.isEmpty ? nil : tabs[safeIndex].id
        }
    }

    func selectTab(id: UUID) {
        if tabs.contains(where: { $0.id == id }) {
            activeTabID = id
        }
    }

    /// Attempt to capture the agent session ID from the terminal buffer.
    /// Call this a few seconds after an agent tab is created.
    func captureSessionID(for tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[idx].agent != nil,
              tabs[idx].sessionID == nil,
              let surface = tabs[idx].viewModel.surfaceTree.first?.surface else { return }

        if let id = AgentSessionCapture.captureSessionID(from: surface, agent: tabs[idx].agent!) {
            tabs[idx].sessionID = id
        }
    }
}

/// Caches per-workspace tab groups so workspace switching is instant.
/// View models and terminal surfaces stay alive across switches.
final class WorkspaceViewModelCache: ObservableObject {

    private var cache: [UUID: WorkspaceTabGroup] = [:]
    private var defaultGroup: WorkspaceTabGroup?

    /// Get or create the tab group for a workspace.
    func tabGroup(
        for workspace: Workspace?,
        app: ghostty_app_t,
        baseConfig: Ghostty.SurfaceConfiguration? = nil
    ) -> WorkspaceTabGroup {
        if let workspace {
            if let existing = cache[workspace.id] { return existing }
            let group = WorkspaceTabGroup()

            // Try restore all tabs from saved session
            if let session = WorkspacePersistence().loadSession(workspaceID: workspace.id),
               !session.tabs.isEmpty {
                for (i, tabState) in session.tabs.enumerated() {
                    let vm = WorkspaceTerminalViewModel()
                    var config = baseConfig ?? Ghostty.SurfaceConfiguration()

                    // Resume agent if one was running in this tab
                    if let agent = tabState.agent {
                        config.initialInput = agent.resumeCommand(sessionID: tabState.sessionID) + "\n"
                    }

                    vm.surfaceTree = tabState.splitLayout.toSplitTree(app: app, baseConfig: config)
                    let entry = WorkspaceTabEntry(title: tabState.title, viewModel: vm, agent: tabState.agent, sessionID: tabState.sessionID)
                    group.addTab(entry, activate: i == session.activeTabIndex)
                }
            } else if let agent = workspace.agent, workspace.taskDescription != nil {
                // Auto-launch agent with task for new workspaces
                var config = baseConfig ?? Ghostty.SurfaceConfiguration()
                var input = agent.launchCommand
                if let task = workspace.taskDescription, !task.isEmpty {
                    input += "\n" + task
                }
                config.initialInput = input + "\n"
                let vm = WorkspaceTerminalViewModel()
                vm.surfaceTree = SplitTree(view: Ghostty.SurfaceView(app, baseConfig: config))
                group.addTab(WorkspaceTabEntry(title: agent.displayName, viewModel: vm, agent: agent))
            } else {
                let vm = createViewModel(app: app, baseConfig: baseConfig, workspace: workspace)
                group.addTab(WorkspaceTabEntry(title: "", viewModel: vm))
            }

            cache[workspace.id] = group
            return group
        } else {
            if let existing = defaultGroup { return existing }
            let group = WorkspaceTabGroup()
            let vm = createViewModel(app: app, baseConfig: baseConfig, workspace: nil)
            group.addTab(WorkspaceTabEntry(title: "", viewModel: vm))
            defaultGroup = group
            return group
        }
    }

    /// Create a new tab in a workspace's group.
    func createTab(
        for workspace: Workspace?,
        app: ghostty_app_t,
        baseConfig: Ghostty.SurfaceConfiguration? = nil,
        title: String = "Shell",
        agent: AgentType? = nil,
        taskDescription: String? = nil
    ) -> WorkspaceTabEntry {
        let group = tabGroup(for: workspace, app: app, baseConfig: baseConfig)

        var config = baseConfig ?? Ghostty.SurfaceConfiguration()
        if let agent {
            var input = agent.launchCommand
            // If there's a task description, send it as the initial prompt after the agent launches
            let task = taskDescription ?? workspace?.taskDescription
            if let task, !task.isEmpty {
                // For Claude: pass task via -p flag; for others: send as follow-up input
                switch agent {
                case .claude:
                    input = "claude -p \"\(task.replacingOccurrences(of: "\"", with: "\\\""))\""
                default:
                    input += "\n" + task
                }
            }
            config.initialInput = input + "\n"
        }

        let vm = WorkspaceTerminalViewModel()
        vm.surfaceTree = SplitTree(view: Ghostty.SurfaceView(app, baseConfig: config))
        let entry = WorkspaceTabEntry(title: title, viewModel: vm, agent: agent)
        group.addTab(entry)
        return entry
    }

    /// All tab groups for persistence.
    var allGroups: [(UUID?, WorkspaceTabGroup)] {
        var result: [(UUID?, WorkspaceTabGroup)] = []
        if let def = defaultGroup { result.append((nil, def)) }
        for (id, group) in cache { result.append((id, group)) }
        return result
    }

    // MARK: - Private

    private func createViewModel(
        app: ghostty_app_t,
        baseConfig: Ghostty.SurfaceConfiguration?,
        workspace: Workspace?
    ) -> WorkspaceTerminalViewModel {
        let vm = WorkspaceTerminalViewModel()
        let config = baseConfig ?? Ghostty.SurfaceConfiguration()

        // Try restore from session
        if let workspace,
           let session = WorkspacePersistence().loadSession(workspaceID: workspace.id),
           let tab = session.tabs.first {
            vm.surfaceTree = tab.splitLayout.toSplitTree(app: app, baseConfig: config)
        } else {
            vm.surfaceTree = SplitTree(view: Ghostty.SurfaceView(app, baseConfig: config))
        }
        return vm
    }
}
