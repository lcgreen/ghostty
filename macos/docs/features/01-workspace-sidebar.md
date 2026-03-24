# Workspace Sidebar

## Overview

`WorkspaceSidebar` is the primary navigation component of the Ghostset workspace orchestration layer. It renders a vertical sidebar containing a header toolbar, optional search/filter/tag bar, a scrollable list of workspace rows, and an optional git status panel. The sidebar enables users to create, search, filter, sort, tag, rename, archive, pin, and delete workspaces, as well as open them in external editors and manage templates/environments. It is built entirely in SwiftUI and communicates with `WorktreeManager` (the central state manager) and `WorkspaceNotifier` (activity/unread tracking).

## Architecture

### Key Files

| File | Role |
|------|------|
| `Sources/Features/Workspace/WorkspaceSidebar.swift` | Main sidebar view (639 lines) |
| `Sources/Features/Workspace/WorkspaceRow.swift` | Individual workspace row component (164 lines) |
| `Sources/Features/Workspace/WorkspaceModel.swift` | `Workspace` struct, `WorkspaceStatus`, `WorkspaceSortOrder`, `WorkspaceFilter`, `WorkspaceConfig`, `EnvironmentProfile`, `WorkspaceChangeStats` |
| `Sources/Features/Workspace/TagDefinition.swift` | Tag model with colors, icons, auto-tagging, language detection |
| `Sources/Features/Workspace/GitStatusPanel.swift` | VS Code-style source control panel shown below workspace list |
| `Sources/Features/Workspace/WorktreeManager.swift` | Central state manager: CRUD operations, persistence, git worktrees |
| `Sources/Features/Workspace/WorkspaceNotifier.swift` | Activity monitoring, unread badges, macOS notifications |
| `Sources/Features/Workspace/WorkspaceHelpers.swift` | `AgentColors`, `GitShell`, `FuzzyMatch`, `ConventionalCommit` utilities |
| `Sources/Features/Workspace/NewWorkspaceSheet.swift` | Modal sheet for creating new workspaces |
| `Sources/Features/Workspace/WorkspaceDiffView.swift` | Cross-workspace diff comparison sheet |
| `Sources/Features/Workspace/TemplateManagerView.swift` | Template management sheet |
| `Sources/Features/Workspace/EnvironmentManagerView.swift` | Environment profile management sheet |
| `Sources/Features/Workspace/WorkspaceSettingsPopover.swift` | Per-workspace settings popover |

### Data Models

| Model | Type | Purpose |
|-------|------|---------|
| `Workspace` | `struct` (Codable, Identifiable, Hashable) | Core workspace entity with id, name, repoPath, worktreePath, branch, createdAt, agent, status, tags, taskDescription, isPinned, isArchived, sortOrder |
| `WorkspaceStatus` | `enum` (Codable) | Cases: `.creating`, `.ready`, `.running(pid:)`, `.stopped`, `.error(String)` |
| `WorkspaceSortOrder` | `enum` (String, CaseIterable, Codable) | Cases: `.manual`, `.name`, `.dateCreated`, `.status`, `.changeCount` |
| `WorkspaceFilter` | `enum` (String, CaseIterable) | Cases: `.active`, `.archived`, `.all` |
| `TagDefinition` | `struct` (Codable, Identifiable, Hashable) | Tag with name, colorName, optional iconName, optional parentTag |
| `WorkspaceChangeStats` | `struct` (Equatable) | additions, deletions, filesChanged for git diff stats |
| `GitFileChange` | `struct` (Identifiable) | path, status, isStaged, additions, deletions |
| `GitFileStatus` | `enum` | Cases: `.modified`, `.added`, `.deleted`, `.renamed`, `.untracked`, `.conflicted` |

### Feature Connections

| Connected Feature | Integration Point |
|-------------------|-------------------|
| `WorkspaceWindow` | Parent view embeds `WorkspaceSidebar` in `NavigationSplitView` sidebar column |
| `WorktreeManager` | Passed as `@ObservedObject`; all CRUD operations go through it |
| `WorkspaceNotifier` | Accessed via `manager.notifier`; drives unread badges and `markRead()` |
| `NewWorkspaceSheet` | Presented as `.sheet`; receives `manager`, calls back with created workspace |
| `WorkspaceDiffView` | Presented as `.sheet`; receives `manager` |
| `TemplateManagerView` | Presented as `.sheet`; receives `manager` |
| `EnvironmentManagerView` | Presented as `.sheet`; receives `manager` |
| `WorkspaceSettingsPopover` | Presented as `.popover`; receives `manager` and specific `workspace` |
| `GitStatusPanel` | Embedded inline at bottom of sidebar when `showingGitPanel` is true |
| `WorkspaceRow` | Rendered for each workspace in the list |
| `FuzzyMatch` | Used for search scoring against workspace name, branch, and tags |
| `AgentColors` | Used by `WorkspaceRow` to color agent icons |
| `GitShell` | Used by `WorkspaceRow` to load per-workspace change stats |

## Current Implementation

### UI Elements

#### Header Bar (top of sidebar)
- **"Workspaces" label**: `Text("Workspaces")` with `.font(.system(size: 11, weight: .semibold))`, `.foregroundStyle(.secondary)`, `.textCase(.uppercase)`
- **Search toggle button**: SF Symbol `magnifyingglass`, size 10, toggles `showingSearch`; foreground is `.primary` when active, `.secondary` when inactive
- **Sort menu button**: SF Symbol `arrow.up.arrow.down`, size 10; `.menuStyle(.borderlessButton)`; foreground is `.primary` when non-manual sort, `.secondary` when manual; contains one `Button` per `WorkspaceSortOrder.allCases` with checkmark indicator
- **Git panel toggle button**: SF Symbol `arrow.triangle.branch`, size 10; toggles `showingGitPanel`; help text "Toggle git changes"
- **Add menu**: SF Symbol `plus`, size 11, `.foregroundStyle(.secondary)`, `.menuStyle(.borderlessButton)`:
  - "New Workspace" (icon: `plus.rectangle.on.rectangle`) — presents `NewWorkspaceSheet`
  - "Open Project" (icon: `folder`) — opens folder picker to register existing git repo
  - Divider
  - "New Tag" (icon: `tag`) — opens new tag popover
  - "Manage Templates" (icon: `doc.on.doc`) — presents `TemplateManagerView`
  - "Environments" (icon: `server.rack`) — presents `EnvironmentManagerView`
  - Divider
  - "Compare All Workspaces" (icon: `square.split.2x1`) — presents `WorkspaceDiffView`

#### Search Bar (conditional, shown when `showingSearch` is true)
- **Search icon**: SF Symbol `magnifyingglass`, size 10, `.foregroundStyle(.tertiary)`
- **Text field**: `TextField("Search", text: $searchText)`, `.textFieldStyle(.plain)`, `.font(.system(size: 11))`
- **Clear button** (conditional, shown when `searchText` is not empty): SF Symbol `xmark.circle.fill`, size 10, `.foregroundStyle(.tertiary)`
- Background: `Color.primary.opacity(0.04)`, corner radius 6

#### Tag Bar (conditional, shown when `showingSearch` is true AND tags exist)
- **"All" pill**: Always first; uses `.secondary` color; selected when `selectedTag == nil`
- **Per-tag pills**: One per unique tag across all workspaces; shows:
  - Optional SF Symbol icon from `TagDefinition.iconName` (size 8)
  - Tag name label (size 10, weight `.medium` when selected, `.regular` otherwise)
  - Optional usage count badge (size 8, `.foregroundStyle(.tertiary)`)
  - Capsule background: selected = `color.opacity(0.15)`, unselected = `Color.primary.opacity(0.04)`
- Tapping a selected tag deselects it (sets `selectedTag = nil`); tapping an unselected tag selects it

#### Filter Picker (conditional, shown when `showingSearch` is true)
- `Picker("Filter", selection: $workspaceFilter)` with `.pickerStyle(.segmented)`, `.controlSize(.small)`
- Segments: "Active", "Archived", "All" (from `WorkspaceFilter.allCases`)

#### Divider
- `Divider().opacity(0.4).padding(.top, 4).padding(.bottom, 6)` between header area and workspace list

#### Workspace List
- `List(selection: $selectedWorkspaceID)` with `.listStyle(.sidebar)`
- **Empty state (no workspaces at all)**: Icon `rectangle.stack.badge.plus` (title2 size, `.foregroundStyle(.tertiary)`), text "No workspaces" (size 12, `.foregroundStyle(.secondary)`)
- **Empty state (no matches)**: Icon `magnifyingglass`, text "No matches"
- **Workspace rows**: `ForEach(filteredWorkspaces)` rendering `WorkspaceRow` or inline rename `TextField`
  - Supports `.onMove` for drag reorder (calls `manager.moveWorkspaces(from:to:)`)
  - Double-tap activates inline rename mode
  - Each row has a `.contextMenu`

#### WorkspaceRow (per-workspace)
- **Agent icon**: SF Symbol from `AgentType.iconName` (size 11), colored via `AgentColors.color(for:)`; falls back to `terminal` icon in `.secondary` if no agent
- **Workspace name**: size 13, weight `.medium`, 1-line limit
- **Pin indicator** (conditional): SF Symbol `pin.fill` (size 8), `.foregroundColor(.orange.opacity(0.7))`
- **Branch label** (conditional, hidden if branch == name): monospaced size 10, `.foregroundStyle(.secondary)`, abbreviates `ghostset/` prefix
- **Tag pills** (conditional): Up to 3 pills shown, each as capsule with tag color; overflow shown as "+N" count
- **Status dot**: 6x6 `Circle` filled with status color (orange if unread, else status-dependent); animates pulse when `hasUnread`
- **Change stats** (conditional): `+N` in green, `-N` in red, monospaced size 9
- **Hover tooltip**: Shows branch, file change summary, status label
- **Archived opacity**: `0.5` when `workspace.isArchived`
- Loads git `--shortstat` asynchronously via `.task(id: workspace.id)`

#### Inline Rename Field
- `TextField("Name", text: $renameText, onCommit:)`, `.textFieldStyle(.plain)`, `.font(.system(size: 12))`
- Escape key cancels via `.onExitCommand`
- Commit calls `workspace.renamed(to:)` then `manager.updateWorkspace()`

#### Context Menu (right-click on workspace row)
1. **"Open in Finder"** — opens worktree path in Finder
2. **"Rename..."** — enters inline rename mode
3. Divider
4. **"Pin to Top" / "Unpin"** — toggles pin state
5. **"Archive" / "Unarchive"** — toggles archive state
6. Divider
7. **"Tags" submenu** — tag toggles with colored circles + "Manage Tags..."
8. Divider
9. **"Settings..."** — opens `WorkspaceSettingsPopover`
10. **"Save as Template"** — captures workspace layout as reusable template
11. **"Apply Template" submenu** — lists all templates; shows confirmation alert, prompts for variables if defined, applies layout with auto-run commands
12. **"Open in VS Code"** / **"Open in Cursor"** — launches editor at worktree path (graceful nil handling)
13. Divider
14. **"Remove from Workspace"** — soft remove (keeps files), shows confirmation alert
15. **"Delete Worktree"** (destructive) — hard delete with confirmation, shows "Deleting..." status, error feedback on failure

#### Delete Confirmation Alert
- Title: "Delete Worktree?" (hard delete) or "Remove Workspace?" (soft remove)
- Message: describes consequence (files deleted vs. files kept)
- Buttons: "Delete"/"Remove" (role: `.destructive`) and "Cancel" (role: `.cancel`)
- Hard delete: calls `manager.deleteWorkspace(ws)` via async Task
- Soft remove: calls `manager.untrackWorkspace(ws)`
- Both: if deleted workspace was selected, selects first remaining workspace

#### New Tag Popover
- **Title**: "New Tag" (size 12, weight `.semibold`)
- **Name field**: `TextField("Tag name")`, `.textFieldStyle(.roundedBorder)`, `.font(.system(size: 12))`
- **Color grid**: `LazyVGrid` with 5 columns, 6px spacing; 10 color swatches as 20x20 circles with white stroke border (2pt) and shadow when selected
- **Available colors**: blue, indigo, purple, pink, red, orange, yellow, green, teal, mint
- **Cancel button**: `.buttonStyle(.plain)`, `.foregroundStyle(.secondary)`
- **Add button**: `.buttonStyle(.borderedProminent)`, `.controlSize(.small)`, disabled when name is empty
- Tag name processing: trimmed, lowercased, spaces replaced with hyphens
- Calls `manager.upsertTagDefinition(TagDefinition(name:colorName:))`
- Frame width: 180, padding: 12

#### Git Status Panel (conditional, shown when `showingGitPanel` is true AND a workspace is selected)
- Separated by `Divider().opacity(0.3)`
- **Loading state**: `ProgressView` with "Loading..." text
- **Empty state**: Checkmark circle icon + "Working tree clean"
- **Commit input**: TextField "Commit message" + checkmark commit button (green, shown when message + staged files) + push button (arrow.up)
- **File list**: Each file shows status icon (colored by type), monospaced path, +/- line counts, stage/unstage button
- Git operations: stage, unstage, stageAll, unstageAll, commit, push
- Refreshes on `NSApplication.didBecomeActiveNotification`

### User Interactions

| Interaction | Target | Effect |
|-------------|--------|--------|
| Click search button | Header | Toggle search bar, tag bar, and filter picker with animation |
| Click sort menu | Header | Change `sortOrder` among Manual/Name/Date Created/Status/Changes |
| Click git toggle | Header | Show/hide `GitStatusPanel` at bottom of sidebar |
| Click add menu items | Header | Present respective sheets/popovers |
| Type in search field | Search bar | Fuzzy-filter workspaces by name, branch, and tags |
| Click clear (x) button | Search bar | Clear search text |
| Click tag pill | Tag bar | Filter workspaces by tag; click again to deselect |
| Select filter segment | Filter picker | Filter by Active/Archived/All |
| Click workspace row | List | Select workspace (updates `selectedWorkspaceID`), marks as read |
| Double-click workspace row | List | Enter inline rename mode |
| Press Enter in rename field | Rename field | Commit rename |
| Press Escape in rename field | Rename field | Cancel rename |
| Drag workspace row | List | Reorder via `.onMove` |
| Right-click workspace row | List | Show context menu |
| Click "Open in Finder" | Context menu | Opens worktree path in Finder |
| Click "Pin to Top"/"Unpin" | Context menu | Toggle pin state; pinned items sort first |
| Click "Archive"/"Unarchive" | Context menu | Toggle archive state; archived items hidden in "Active" filter |
| Click tag in Tags submenu | Context menu | Toggle tag on/off for workspace |
| Click "Settings..." | Context menu | Show `WorkspaceSettingsPopover` |
| Click "Save as Template" | Context menu | Save workspace configuration as reusable template |
| Click "Open in VS Code" | Context menu | Launch VS Code at worktree path |
| Click "Open in Cursor" | Context menu | Launch Cursor at worktree path |
| Click "Remove from Workspace" | Context menu | Show soft-delete confirmation alert |
| Click "Delete Worktree" | Context menu | Show hard-delete confirmation alert |
| Confirm delete/remove | Alert | Execute deletion, reselect first workspace |

### State Properties

#### @ObservedObject
| Property | Type | Purpose |
|----------|------|---------|
| `manager` | `WorktreeManager` | Central state manager providing `workspaces`, `tagDefinitions`, `notifier`, and all CRUD methods |

#### @Binding
| Property | Type | Purpose |
|----------|------|---------|
| `selectedWorkspaceID` | `UUID?` | Two-way binding to the currently selected workspace; drives `List(selection:)` and detail view |

#### @State (private)
| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `showingNewWorkspace` | `Bool` | `false` | Controls `NewWorkspaceSheet` presentation |
| `workspaceToDelete` | `Workspace?` | `nil` | Workspace pending deletion; non-nil triggers alert |
| `deleteFromDisk` | `Bool` | `false` | Whether pending delete is hard (disk) or soft (untrack) |
| `searchText` | `String` | `""` | Current search query for fuzzy filtering |
| `showingSearch` | `Bool` | `false` | Whether search bar, tag bar, and filter picker are visible |
| `selectedTag` | `String?` | `nil` | Currently selected tag for filtering; nil means "All" |
| `showingNewTag` | `Bool` | `false` | Controls new tag popover presentation |
| `newTagName` | `String` | `""` | Text input for new tag name |
| `newTagColor` | `String` | `"blue"` | Selected color for new tag |
| `showingGitPanel` | `Bool` | `false` | Whether `GitStatusPanel` is visible |
| `showingDiffView` | `Bool` | `false` | Controls `WorkspaceDiffView` sheet presentation |
| `showingTemplates` | `Bool` | `false` | Controls `TemplateManagerView` sheet presentation |
| `showingEnvironments` | `Bool` | `false` | Controls `EnvironmentManagerView` sheet presentation |
| `settingsWorkspace` | `Workspace?` | `nil` | Workspace for settings popover; non-nil triggers popover |
| `sortOrder` | `WorkspaceSortOrder` | `.manual` | Current sort order for workspace list |
| `workspaceFilter` | `WorkspaceFilter` | `.active` | Current archive filter |
| `renamingWorkspace` | `Workspace?` | `nil` | Workspace currently being renamed inline |
| `renameText` | `String` | `""` | Text buffer for inline rename field |
| `multiSelection` | `Set<UUID>` | `[]` | Multi-selection set (declared but not yet used in UI) |

### Notifications

| Notification Name | Direction | Effect |
|-------------------|-----------|--------|
| `NSApplication.didBecomeActiveNotification` | Received | Calls `manager.refreshStats()` to update git change stats |
| `ghostset.showDiffView` | Received | Sets `showingDiffView = true` |
| `ghostset.showTemplates` | Received | Sets `showingTemplates = true` |
| `ghostset.toggleGitPanel` | Received | Toggles `showingGitPanel` |
| `ghostset.toggleSearch` | Received | Toggles `showingSearch` with animation |
| `ghostset.sortWorkspaces` | Received | Reads `userInfo["sort"]` string, sets `sortOrder` to `.name`, `.dateCreated`, or `.manual` |
| `ghostset.filterWorkspaces` | Received | Reads `userInfo["filter"]` string, sets `workspaceFilter` to `.active`, `.archived`, or `.all` |

## Design Consistency

### Font Sizes
| Element | Size | Weight | Design |
|---------|------|--------|--------|
| Header "Workspaces" label | 11 | `.semibold` | default |
| Header button icons | 10-11 | default | default |
| Search field text | 11 | default | default |
| Tag pill label | 10 | `.medium` (selected) / `.regular` | default |
| Tag pill count badge | 8 | `.medium` | default |
| Tag pill icon | 8 | default | default |
| Workspace name | 13 | `.medium` | default |
| Branch label | 10 | default | `.monospaced` |
| Tag pills in row | 9 | `.medium` | default |
| Tag overflow "+N" | 8 | default | default |
| Change stats | 9 | default | `.monospaced` |
| Pin icon | 8 | default | default |
| Agent icon | 11 | default | default |
| Status dot | 6x6 | n/a | n/a |
| Empty state message | 12 | default | default |
| Rename field | 12 | default | default |
| New tag popover title | 12 | `.semibold` | default |
| New tag popover field | 12 | default | default |

### Spacing/Padding Values
| Location | Values |
|----------|--------|
| Header horizontal padding | 12 |
| Header top padding | 6 |
| Header bottom padding | 2 |
| Search bar horizontal padding | 10 (outer), 8 (inner) |
| Search bar vertical padding | 5 (inner), 4 (bottom outer) |
| Search bar corner radius | 6 |
| Tag bar horizontal padding | 10 |
| Tag bar bottom padding | 4 |
| Tag pill horizontal padding | 8 |
| Tag pill vertical padding | 3 |
| Tag pill spacing | 4 (between pills), 3 (internal) |
| Filter picker horizontal padding | 10 |
| Filter picker bottom padding | 4 |
| Divider after header | opacity 0.4, top 4, bottom 6 |
| Divider before git panel | opacity 0.3 |
| Workspace row vertical padding | 6 |
| Workspace row internal spacing | 10 (main HStack), 2 (name VStack) |
| Empty placeholder top padding | 32 |
| Empty placeholder spacing | 6 |
| New tag popover padding | 12 |
| New tag popover width | 180 |
| Color swatch size | 20x20 |
| Color swatch grid spacing | 6 |
| Sidebar minimum width | 220 |

### Color Usage
| Element | Color |
|---------|-------|
| Header label | `.secondary` |
| Inactive header buttons | `.secondary` |
| Active header buttons | `.primary` |
| Search field background | `Color.primary.opacity(0.04)` |
| Search icon | `.tertiary` |
| Clear search button | `.tertiary` |
| Unselected tag pill background | `Color.primary.opacity(0.04)` |
| Selected tag pill background | `tagColor.opacity(0.15)` |
| Selected tag pill text | `.primary` |
| Unselected tag pill text | `.secondary` |
| Status dot (unread) | `.orange` |
| Status dot (creating) | `.secondary` |
| Status dot (ready) | `.blue` |
| Status dot (running) | `.green` |
| Status dot (stopped) | `.gray` |
| Status dot (error) | `.red` |
| Pin icon | `.orange.opacity(0.7)` |
| Additions text | `.green.opacity(0.8)` |
| Deletions text | `.red.opacity(0.8)` |
| Archived row opacity | 0.5 |
| Tag pill border | `color.opacity(0.25)`, lineWidth 0.5 |
| Tag pill background | `color.opacity(0.18)` |
| Tag pill text | `color.opacity(0.9)` |

### SwiftUI Patterns
- Uses `@ViewBuilder` for conditional views (`tagBar`, `contextMenu`, `deleteAlert`, `workspaceRowView`)
- Extracted computed properties for each visual section: `header`, `searchBar`, `tagBar`, `workspaceList`, `sortMenuButton`, `addMenu`, `newTagPopover`, `deleteAlert`
- Helper functions for reusable components: `tagBarPill()`, `emptyPlaceholder()`, `colorSwatch()`, `renameField()`, `workspaceRowView()`
- Animation: `.easeInOut(duration: 0.15)` for search toggle; `.easeInOut(duration: 0.6).repeatForever(autoreverses: true)` for unread pulse
- Conditional presentation via optional-to-Bool binding pattern for `settingsWorkspace` and `workspaceToDelete`
- `.task(id:)` for async data loading in `WorkspaceRow`

## Ghostty Codebase Alignment

### Ghostty Types Used
- **None directly.** `WorkspaceSidebar` operates entirely within the Ghostset workspace layer and does not import or reference `GhosttyKit`, `Ghostty.App`, or any Ghostty terminal surface types.

### Integration Points
- `WorktreeManager` is initialized with `Ghostty.App` and acts as the bridge
- `WorkspaceWindow` (the parent view) handles the terminal detail pane via `Ghostty.SurfaceForApp`
- Workspace selection in the sidebar drives which terminal surface is shown in the detail pane
- Sidebar is embedded in `NavigationSplitView` sidebar column within `WorkspaceWindow`

### Potential Conflicts
- Sidebar width (min 220) may conflict with Ghostty's existing split pane behavior if both are active in the same window
- Notification names use `ghostset.` prefix which avoids collision with Ghostty's notification namespace
- The `List(selection:)` pattern assumes single selection but `multiSelection` state exists unused, suggesting multi-select is planned

## Known Issues

1. **Git panel is global, not per-workspace.** `showingGitPanel` is sidebar-wide. Panel stays open when switching workspaces — content updates but this may be confusing.
2. **Cursor bundle ID is fragile.** `com.todesktop.230313mzl4w4u92` is a ToDesktop-generated ID that may change between Cursor releases. Noted in code with a comment.
3. **`changeCount` sort is approximate.** Change stats are loaded async per-row and not available to the sidebar sort logic. Falls back to name comparison.

## Resolved Issues (previously known)

| Issue | Resolution |
|-------|-----------|
| `multiSelection` dead code | Removed |
| `toggleTag` mutates copy incorrectly | Cleaned up, uses immutable pattern |
| Force-unwrap in tag filtering | Replaced with safe optional chaining |
| Search reset doesn't clear `selectedTag` | Fixed — `selectedTag = nil` on search dismiss |
| `openInEditor` hardcoded fallback path | Fixed — graceful nil handling with `Ghostty.logger` warning |
| Delete alert swallows errors | Fixed — `do/catch` with `deleteError` alert |

## Future Enhancements

1. **Multi-select operations.** Bulk archive, bulk tag, bulk delete for selected workspaces.
2. **True change-count sorting.** Propagate `WorkspaceChangeStats` up from `WorkspaceRow` to sidebar sort.
3. **Tag management improvements.** Rename tags, delete tags, hierarchical tags (`parentTag` exists but unused).
4. **Keyboard shortcuts.** Arrow keys between workspaces, Cmd+F for search, Cmd+N for new workspace.
5. **Drag-and-drop to tag.** Drag workspaces onto tag pills to assign tags.
6. **Persist sidebar state.** Save `sortOrder`, `showingGitPanel`, `selectedTag` to UserDefaults.
7. **External editor configurability.** User-configurable editor list instead of hardcoded VS Code + Cursor.

## Recently Added (2026-03-24)

| Feature | Implementation |
|---------|----------------|
| **Apply Template** context menu | Right-click → Apply Template with confirmation alert; prompts for variables if defined |
| **Open Project** | "+" menu → Open Project opens folder picker to register existing git repo |
| **Template indicator** | Workspace row shows assigned template name as capsule pill |
| **Deleting status** | Orange `.deleting` status during async worktree deletion |
| **Variable prompt** | `TemplateVariablePrompt` sheet shown when applying template with variables |
| **Lifecycle commands** | `onCreateCommand` runs on apply, `onDestroyCommand` runs before delete |
| **Branch validation** | Validates branch exists before worktree creation; visual indicator in NewWorkspaceSheet |

## Changelog

- 2026-03-20: Initial spec
- 2026-03-24: Fixed: openInEditor nil handling, delete error feedback, search reset, force-unwrap
- 2026-03-24: Added: Apply Template with confirmation, Open Project, template indicator, deleting status, variable prompt, lifecycle commands, branch validation
