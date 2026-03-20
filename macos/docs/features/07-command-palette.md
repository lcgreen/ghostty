# Command Palette

## Overview

WorkspaceCommandPalette is a Cmd+K activated command palette providing fuzzy-searchable access to workspace switching, git commands, agent launching, template management, tag filtering, and workspace management actions. It features categorized results with recent action tracking, keyboard navigation, and dynamic "create workspace" suggestions when the query starts with "new" or "create".

## Architecture

### Key Files

| File | Role |
|------|------|
| `Sources/Features/Workspace/WorkspaceCommandPalette.swift` | Full palette UI, result building, fuzzy matching, keyboard handling |

### Data Models

**PaletteResult** (struct)
- `id: String` -- unique identifier (e.g., `"ws-{uuid}"`, `"action-new"`, `"git-commit"`)
- `title: String` -- display title
- `subtitle: String?` -- secondary description
- `icon: String` -- SF Symbol name
- `iconColor: Color` -- icon tint color (default: `.secondary`)
- `shortcut: String?` -- keyboard shortcut hint (e.g., `"Cmd+N"`)
- `category: String` -- grouping category (default: `"Actions"`)
- `score: Int` -- fuzzy match score (default: 0)
- `action: () -> Void` -- closure executed on selection

**ResultGroup** (private struct)
- `category: String` -- section title
- `results: [PaletteResult]` -- items in this group

**PaletteTextField** (NSViewRepresentable struct)
- Bridges an `NSTextField` into SwiftUI for custom keyboard event handling
- Properties: `text: Binding<String>`, `onSubmit`, `onArrowUp`, `onArrowDown`, `onEscape`
- Coordinator class implements `NSTextFieldDelegate` to intercept `moveUp`, `moveDown`, `cancelOperation`, `insertNewline` selectors

### Feature Connections

- **WorktreeManager** -- provides workspaces, templates, tag definitions
- **FuzzyMatch** -- scoring engine via `FuzzyMatch.score(query:target:)`
- **AgentType** -- `.builtIn` array for agent launcher results
- **AgentColors** -- agent-specific color via `AgentColors.color(for:)`
- **NSWorkspace** -- opens files in Finder, VS Code, and Cursor
- **UserDefaults** -- persists recent actions under `ghostset.recentPaletteActions`
- **NotificationCenter** -- posts `ghostset.*` notifications for actions

## Current Implementation

### State Properties

| Property | Type | Purpose |
|----------|------|---------|
| `manager` | `@ObservedObject WorktreeManager` | Source of workspaces, tags, templates |
| `selectedWorkspaceID` | `@Binding UUID?` | Currently selected workspace, updated on workspace switch |
| `isPresented` | `@Binding Bool` | Controls palette visibility |
| `query` | `@State String` | Current search text |
| `selectedIndex` | `@State Int` | Index of highlighted result in filtered list |
| `recentActionIDs` | `@State [String]` | Recently executed action IDs (max 5) |
| `isFocused` | `@FocusState Bool` | Focus state for the search field |

### Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `recentsKey` | `"ghostset.recentPaletteActions"` | UserDefaults key for recent actions |
| `maxRecents` | `5` | Maximum number of tracked recent actions |

### UI Elements

**Search Field**
- `magnifyingglass` icon (`.system(size: 14)`, `.tertiary`)
- `PaletteTextField` with placeholder "Search workspaces, actions..."
- Font size: 15 (on the NSTextField)
- Padding: horizontal 14, vertical 12
- Resets `selectedIndex` to 0 on query change

**Results List**
- `ScrollViewReader` + `ScrollView` with max height 300
- Grouped by category with section headers
- Empty state: "No results" text (`.system(size: 12)`, `.tertiary`, padding 12)
- Auto-scrolls to selected item on `selectedIndex` change

**Section Header** (`sectionHeader(_:)`)
- Text uppercased, `.system(size: 9, weight: .semibold)`, `.tertiary`
- Padding: horizontal 14, top 8, bottom 4

**Result Row** (`resultRow(_:isSelected:)`)
- Icon: `.system(size: 11)`, colored by `iconColor`, frame width 16
- Title: `.system(size: 13)`, single line
- Subtitle: `.system(size: 10)`, `.secondary`, single line
- Shortcut badge: `.system(size: 9, design: .monospaced)`, `.tertiary`, with `.primary.opacity(0.05)` background, cornerRadius 3, padding horizontal 4, vertical 2
- Selected state: `Color.accentColor.opacity(0.15)` background
- Row padding: horizontal 12, vertical 6

**Container**
- Frame width: 420
- Background: `.ultraThinMaterial`
- Corner radius: 12
- Shadow: `Color.black.opacity(0.3)`, radius 20, y offset 10

### Result Categories and Actions

**Workspaces** (`category: "Workspaces"`)
- One result per workspace in `manager.workspaces`
- ID: `"ws-{uuid}"`
- Icon: workspace agent icon or `"terminal"`
- Action: sets `selectedWorkspaceID` and dismisses palette

**Actions** (`category: "Actions"`)
- "New Workspace" (ID: `"action-new"`, shortcut: `Cmd+N`) -- posts `ghostset.newWorkspace` notification
- Dynamic "Create workspace: {name}" (ID: `"action-create-dynamic"`) -- appears when query starts with "new " or "create ", posts `ghostset.newWorkspace` with name info
- "Pin Workspace" / "Unpin Workspace" (ID: `"ws-pin"`) -- toggles pin on selected workspace
- "Archive Workspace" / "Unarchive Workspace" (ID: `"ws-archive"`) -- toggles archive on selected workspace
- "Open in Finder" (ID: `"ws-open-finder"`) -- opens worktree path in Finder
- "Open in VS Code" (ID: `"ws-open-vscode"`) -- opens worktree in VS Code (bundle ID: `com.microsoft.VSCode`)
- "Open in Cursor" (ID: `"ws-open-cursor"`) -- opens worktree in Cursor (bundle ID: `com.todesktop.230313mzl4w4u92`)
- "Compare All Workspaces" (ID: `"view-diff"`, shortcut: `Cmd+Shift+D`) -- posts `ghostset.showDiffView`
- "Manage Templates" (ID: `"view-templates"`) -- posts `ghostset.showTemplates`
- "Toggle Git Panel" (ID: `"view-git"`) -- posts `ghostset.toggleGitPanel`
- "Toggle Search" (ID: `"view-search"`, shortcut: `Cmd+F`) -- posts `ghostset.toggleSearch`
- "Sort by Name" (ID: `"sort-name"`) -- posts `ghostset.sortWorkspaces` with `["sort": "name"]`
- "Sort by Date Created" (ID: `"sort-date"`) -- posts `ghostset.sortWorkspaces` with `["sort": "dateCreated"]`
- "Show Active Workspaces" (ID: `"filter-active"`) -- posts `ghostset.filterWorkspaces` with `["filter": "active"]`
- "Show Archived Workspaces" (ID: `"filter-archived"`) -- posts `ghostset.filterWorkspaces` with `["filter": "archived"]`

**Git** (`category: "Git"`)
- "Git: Commit" (ID: `"git-commit"`) -- posts `ghostset.gitCommit`
- "Git: Push" (ID: `"git-push"`) -- posts `ghostset.gitPush`
- "Git: Pull" (ID: `"git-pull"`) -- posts `ghostset.gitPull`
- "Git: Stash" (ID: `"git-stash"`) -- posts `ghostset.gitStash`

**Agents** (`category: "Agents"`)
- One result per agent in `AgentType.builtIn`
- ID: `"agent-{displayName}"`
- Action: posts `.ghostsetNewWorkspaceTab` notification with `["agent": agent]` userInfo

**Tags** (`category: "Tags"`)
- One result per unique tag across all workspaces
- ID: `"tag-{tagName}"`
- Action: posts `ghostset.filterTag` with `["tag": tag]`

### Methods

| Method | Purpose |
|--------|---------|
| `filteredResults` | Applies fuzzy matching via `FuzzyMatch.score()` against title and subtitle, returns sorted by score descending. Returns all results when query is empty. |
| `groupedResults` | Groups filtered results by category. When query is empty, order is: Recent, Workspaces, Actions, Git, Agents, Tags. When searching, order is: Workspaces, Actions, Git, Agents, Tags. Recent items are excluded from their original category when shown in Recent. |
| `buildResults()` | Constructs the full list of `PaletteResult` items from all categories |
| `moveSelection(_ delta: Int)` | Moves selected index by delta with wraparound |
| `executeSelected()` | Executes the action of the currently selected result |
| `execute(_ result:)` | Tracks the result as recent and calls `result.action()` |
| `trackRecent(_ id: String)` | Adds ID to front of recents list, caps at 5, persists to UserDefaults |
| `postNotification(_ name:info:)` | Posts `Notification.Name("ghostset.\(name)")` with optional userInfo |
| `globalIndex(for:)` | Returns the index of a result in `filteredResults` |
| `workspaceManagementResults()` | Builds pin/archive/open-in-finder/VS Code/Cursor results for the selected workspace |
| `viewResults()` | Builds view toggle and sort/filter action results |
| `gitResults()` | Builds git command results |

### Keyboard Handling

The `PaletteTextField.Coordinator` intercepts these NSResponder selectors:
- `moveUp(_:)` -- calls `onArrowUp`, moves selection up
- `moveDown(_:)` -- calls `onArrowDown`, moves selection down
- `cancelOperation(_:)` -- calls `onEscape`, dismisses palette
- `insertNewline(_:)` -- calls `onSubmit`, executes selected result

### Notification Listeners

- `NSApplication.didBecomeActiveNotification` -- re-focuses the search field when app becomes active

### Array Extension

```swift
extension RandomAccessCollection {
    subscript(safeIndex index: Index) -> Element?
}
```
Returns nil for out-of-bounds access instead of crashing.

## Design Consistency

| Element | Font | Color | Spacing |
|---------|------|-------|---------|
| Search icon | `.system(size: 14)` | `.tertiary` | -- |
| Search field | `.systemFont(ofSize: 15)` | Primary | horizontal 14, vertical 12 |
| Section header | `.system(size: 9, weight: .semibold)` | `.tertiary` | horizontal 14, top 8, bottom 4 |
| Result icon | `.system(size: 11)` | Per-result `iconColor` | frame width 16 |
| Result title | `.system(size: 13)` | Primary | -- |
| Result subtitle | `.system(size: 10)` | `.secondary` | -- |
| Shortcut badge | `.system(size: 9, design: .monospaced)` | `.tertiary` | horizontal 4, vertical 2 |
| Empty text | `.system(size: 12)` | `.tertiary` | padding 12 |
| Container | -- | `.ultraThinMaterial` | width 420, cornerRadius 12 |
| Selected row | -- | `Color.accentColor.opacity(0.15)` | horizontal 12, vertical 6 |
| Shortcut bg | -- | `Color.primary.opacity(0.05)` | cornerRadius 3 |

## Ghostty Codebase Alignment

### Types Used
- `WorktreeManager` (workspaces, tagDefinition(for:), togglePin, toggleArchive)
- `Workspace` (id, name, branch, agent, worktreePath, tags, isPinned, isArchived)
- `AgentType` (.builtIn, displayName, iconName)
- `AgentColors` (color(for:))
- `TagDefinition` (name, color)
- `FuzzyMatch` (score(query:target:))

### Integration Points
- Presented as an overlay in `WorkspaceWindow` body
- Toggled via Cmd+K keyboard shortcut (hidden Button with `.keyboardShortcut("k", modifiers: .command)`)
- Also toggled via `WorkspaceWindowController.toggleCommandPalette(_:)` which sets `terminalViewModel.commandPaletteIsShowing`
- Listens for `ghosttyCommandPaletteDidToggle` notification from Ghostty core
- Posts notifications consumed by WorkspaceSidebar and other views

## Known Issues

1. **Workspace management actions require selection**: Pin/archive/open actions only appear when a workspace is selected, with no indication of this requirement.
2. **No debouncing on search**: Every keystroke triggers full result rebuild and fuzzy matching.
3. **Recent tracking persists action IDs across sessions but not workspace UUIDs**: Workspace-specific recent entries like `"ws-{uuid}"` become stale after workspace deletion.
4. **VS Code/Cursor bundle IDs are hardcoded**: No fallback detection for different installation methods (e.g., Homebrew vs direct download).
5. **Dynamic create result regex is case-insensitive but score is not boosted**: The dynamically created "Create workspace: X" result may rank lower than existing items.
6. **No action for git commands**: The git notifications (`ghostset.gitCommit`, etc.) are posted but their consumers are not clearly documented.

## Future Enhancements

- Add debounced search with a short delay (100-200ms)
- Support keyboard shortcut display with proper glyph rendering
- Add inline previews for workspace results (branch, status, last activity)
- Support custom user-defined commands
- Add "Run in all workspaces" batch actions
- Clean up stale recent entries on workspace deletion
- Add configurable external editor support beyond VS Code and Cursor
- Support command chaining (e.g., "git commit && git push")

## Changelog

- 2026-03-20: Initial spec
