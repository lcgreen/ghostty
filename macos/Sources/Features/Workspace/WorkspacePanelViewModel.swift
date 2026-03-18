import SwiftUI
import GhosttyKit

/// Manages tabs within a workspace panel. Each tab has its own
/// WorkspaceTerminalViewModel (split tree + terminal surfaces).
final class WorkspacePanelViewModel: ObservableObject {

    /// The tab collection (ordered tabs with active selection).
    @Published var tabs: WorkspaceTabCollection = .init()

    /// Per-tab terminal view models, keyed by tab ID.
    private(set) var viewModels: [UUID: WorkspaceTerminalViewModel] = [:]

    /// The ghostty app reference for creating new surfaces.
    private let ghosttyApp: ghostty_app_t

    /// Base surface configuration (workspace working directory, agent env vars).
    private let baseConfig: Ghostty.SurfaceConfiguration?

    /// The active tab's view model, or nil if no tabs exist.
    var activeViewModel: WorkspaceTerminalViewModel? {
        guard let id = tabs.activeTabID else { return nil }
        return viewModels[id]
    }

    /// The active tab ID (for bindings).
    var activeTabID: UUID? { tabs.activeTabID }

    init(app: ghostty_app_t, baseConfig: Ghostty.SurfaceConfiguration? = nil) {
        self.ghosttyApp = app
        self.baseConfig = baseConfig
    }

    // MARK: - Tab Operations

    /// Create a new tab with a fresh terminal surface.
    func createTab() {
        let tab = WorkspaceTab()
        let vm = WorkspaceTerminalViewModel()
        vm.surfaceTree = SplitTree(
            view: Ghostty.SurfaceView(ghosttyApp, baseConfig: baseConfig)
        )
        viewModels[tab.id] = vm
        tabs = tabs.adding(tab)
    }

    /// Close a tab and clean up its terminal surfaces.
    func closeTab(id: UUID) {
        viewModels.removeValue(forKey: id)
        tabs = tabs.removing(id: id)

        // If all tabs closed, create a fresh one
        if tabs.isEmpty {
            createTab()
        }
    }

    /// Close the currently active tab.
    func closeActiveTab() {
        guard let id = tabs.activeTabID else { return }
        closeTab(id: id)
    }

    /// Select a tab by ID.
    func selectTab(id: UUID) {
        tabs = tabs.selecting(id: id)
    }

    /// Select the next tab.
    func selectNextTab() {
        tabs = tabs.selectingNext()
    }

    /// Select the previous tab.
    func selectPreviousTab() {
        tabs = tabs.selectingPrevious()
    }

    /// Update a tab's title (e.g. from pwd changes).
    func updateTabTitle(id: UUID, title: String) {
        tabs = tabs.updatingTitle(id: id, title: title)
    }

    /// Check if a surface view belongs to any tab in this panel.
    func containsSurface(_ view: Ghostty.SurfaceView) -> Bool {
        viewModels.values.contains { $0.surfaceTree.contains(view) }
    }

    /// Find the view model that contains a given surface view.
    func viewModel(for surface: Ghostty.SurfaceView) -> WorkspaceTerminalViewModel? {
        viewModels.values.first { $0.surfaceTree.contains(surface) }
    }
}
