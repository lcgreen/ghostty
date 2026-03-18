import Foundation

/// A single terminal tab within a workspace panel.
struct WorkspaceTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date

    init(id: UUID = UUID(), title: String = "Shell", createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }
}

/// An ordered collection of workspace tabs with an active selection.
/// All mutations return new copies (immutable pattern).
struct WorkspaceTabCollection: Equatable {
    private(set) var tabs: [WorkspaceTab]
    private(set) var activeTabID: UUID?

    init(tabs: [WorkspaceTab] = [], activeTabID: UUID? = nil) {
        self.tabs = tabs
        self.activeTabID = activeTabID ?? tabs.first?.id
    }

    var activeTab: WorkspaceTab? {
        tabs.first { $0.id == activeTabID }
    }

    var count: Int { tabs.count }
    var isEmpty: Bool { tabs.isEmpty }

    /// Add a new tab and make it active.
    func adding(_ tab: WorkspaceTab) -> WorkspaceTabCollection {
        WorkspaceTabCollection(
            tabs: tabs + [tab],
            activeTabID: tab.id
        )
    }

    /// Remove a tab. If the removed tab was active, select the nearest neighbor.
    func removing(id: UUID) -> WorkspaceTabCollection {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return self }

        var newTabs = tabs
        newTabs.remove(at: index)

        let newActiveID: UUID?
        if activeTabID == id {
            // Select the tab at the same index (or the last one)
            if newTabs.isEmpty {
                newActiveID = nil
            } else {
                let safeIndex = min(index, newTabs.count - 1)
                newActiveID = newTabs[safeIndex].id
            }
        } else {
            newActiveID = activeTabID
        }

        return WorkspaceTabCollection(tabs: newTabs, activeTabID: newActiveID)
    }

    /// Select a tab by ID.
    func selecting(id: UUID) -> WorkspaceTabCollection {
        guard tabs.contains(where: { $0.id == id }) else { return self }
        return WorkspaceTabCollection(tabs: tabs, activeTabID: id)
    }

    /// Select the next tab (wrapping).
    func selectingNext() -> WorkspaceTabCollection {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else {
            return self
        }
        let nextIndex = (index + 1) % tabs.count
        return WorkspaceTabCollection(tabs: tabs, activeTabID: tabs[nextIndex].id)
    }

    /// Select the previous tab (wrapping).
    func selectingPrevious() -> WorkspaceTabCollection {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else {
            return self
        }
        let prevIndex = (index - 1 + tabs.count) % tabs.count
        return WorkspaceTabCollection(tabs: tabs, activeTabID: tabs[prevIndex].id)
    }

    /// Update a tab's title.
    func updatingTitle(id: UUID, title: String) -> WorkspaceTabCollection {
        let newTabs = tabs.map { tab in
            tab.id == id ? WorkspaceTab(id: tab.id, title: title, createdAt: tab.createdAt) : tab
        }
        return WorkspaceTabCollection(tabs: newTabs, activeTabID: activeTabID)
    }
}
