# Workspace Diff View

## Overview

WorkspaceDiffView is a cross-workspace diff comparison panel that aggregates and displays git changes from all active workspaces side by side. It allows developers to view file-level diffs, filter by file extension or git status, compare two workspace branches directly, copy patches to the clipboard, and merge branches into main -- all from a single 640x500 modal view.

## Architecture

### Key Files

| File | Role |
|------|------|
| `Sources/Features/Workspace/WorkspaceDiffView.swift` | Full implementation: view, models, git operations |

### Data Models

**WorkspaceDiff** (struct, Identifiable)
- `workspace: Workspace` -- the workspace these changes belong to
- `files: [DiffFile]` -- list of changed files
- `additions: Int` -- total lines added
- `deletions: Int` -- total lines deleted
- `id: UUID` -- derived from `workspace.id`

**DiffFile** (struct)
- `path: String` -- file path relative to worktree
- `status: String` -- git status code: "M" (modified), "A" (added), "D" (deleted), "R" (renamed)
- `additions: Int` -- lines added in this file
- `deletions: Int` -- lines deleted in this file

### Feature Connections

- **WorktreeManager** -- provides the list of workspaces via `manager.workspaces`
- **Workspace** -- supplies `worktreePath`, `repoPath`, `branch`, `name`, `agent`, and `id`
- **GitShell** -- executes async git commands via `GitShell.asyncOutput(_:)`
- **AgentColors** -- provides agent-specific colors via `AgentColors.color(for:)`

## Current Implementation

### State Properties

| Property | Type | Purpose |
|----------|------|---------|
| `manager` | `@ObservedObject WorktreeManager` | Source of workspace data |
| `diffs` | `@State [WorkspaceDiff]` | Loaded diff results for all workspaces |
| `isLoading` | `@State Bool` | Loading spinner state |
| `expandedFiles` | `@State Set<String>` | Tracks which file rows are expanded (keyed by `"workspaceID:filePath"`) |
| `inlineDiffs` | `@State [String: String]` | Cached inline diff content per file key |
| `selectedExtensions` | `@State Set<String>` | File extension filter (empty = show all) |
| `selectedStatuses` | `@State Set<String>` | Git status filter, defaults to `["M", "A", "D", "R"]` |
| `selectedWorkspaces` | `@State Set<UUID>` | Workspace filter (empty = show all) |
| `compareMode` | `@State Bool` | Whether two-workspace comparison mode is active |
| `compareLeft` | `@State UUID?` | Left workspace in compare mode |
| `compareRight` | `@State UUID?` | Right workspace in compare mode |
| `comparisonDiff` | `@State String?` | Output of branch-to-branch diff comparison |
| `mergeTarget` | `@State WorkspaceDiff?` | Workspace targeted for merge-to-main confirmation |

### UI Elements

**Header** (`header`)
- Title: "Workspace Changes" -- `.system(size: 14, weight: .semibold)`
- Toggle: "Compare Two" -- `.switch` style, `.controlSize(.mini)`, bound to `compareMode`
- Refresh button: `arrow.clockwise` icon, `.system(size: 11)`, triggers `loadAllDiffs()`

**Filter Bar** (`filterBar`)
- Extension filter menu: `extensionFilterMenu` -- dropdown listing all unique file extensions found across diffs, with checkmark toggles and a "Clear" action. Label: "Type" with `doc` icon, `.system(size: 10)`, frame width 60.
- Status toggles: Four `Toggle` buttons for "M", "A", "D", "R" -- `.button` style, `.controlSize(.mini)`, tinted by `statusColor()`
- Workspace filter menu: `workspaceFilterMenu` -- dropdown listing all workspaces with checkmark toggles and "Show All" action. Label: "Workspace" with `folder` icon, `.system(size: 10)`, frame width 90.

**Diff List** (`diffList`)
- Loading state: `ProgressView("Scanning workspaces...")` -- `.controlSize(.small)`, centered
- Empty state: `checkmark.circle` icon (`.title2`, `.tertiary`) + "All workspaces clean" text (`.system(size: 12)`, `.secondary`)
- Populated state: `ScrollView` containing `VStack(alignment: .leading, spacing: 0)` of `diffSection` views

**Diff Section** (`diffSection(_:)`) -- per workspace
- Header row with: agent icon (`.system(size: 10)` with agent color), workspace name (`.system(size: 12, weight: .semibold)`), branch name (`.system(size: 10, design: .monospaced)`, `.secondary`), additions/deletions summary (`.system(size: 10, weight: .medium, design: .monospaced)`, green if additions > 0), copy patch button, merge button
- File rows below header

**File Row** (`fileRow(_:workspace:)`)
- Status badge: `.system(size: 9, weight: .bold, design: .monospaced)`, colored by status, frame width 12
- File path: `.system(size: 11, design: .monospaced)`, single line, middle truncation
- Addition count: `+N` in `.system(size: 9, design: .monospaced)`, green
- Deletion count: `-N` in `.system(size: 9, design: .monospaced)`, red
- Chevron: `chevron.down` or `chevron.right` (`.system(size: 8)`, `.tertiary`)
- Tap gesture toggles inline diff expansion

**Diff Block** (`diffBlock(_:)`)
- Displays up to 80 lines of diff output
- Each line: `.system(size: 9, design: .monospaced)`, single line, colored green (additions), red (deletions), or secondary (context)
- Container: padding 6, `.primary.opacity(0.02)` background, cornerRadius 4

**Compare Mode** (`comparisonSection`)
- Two workspace pickers (`workspacePicker`) with "Left" and "Right" labels
- "Compare" button, disabled unless both pickers have different selections
- Comparison diff output displayed in a `ScrollView` with `diffBlock`

**Action Buttons**
- Copy Patch (`copyPatchButton`): `doc.on.clipboard` icon (`.system(size: 9)`), copies full `git diff` output to clipboard via `NSPasteboard`
- Merge (`mergeButton`): `arrow.triangle.merge` icon (`.system(size: 9)`), sets `mergeTarget` to trigger confirmation alert

**Merge Alert**
- Title: "Merge to main?"
- Message: "Merge branch '{branchName}' into main?"
- Buttons: "Cancel" (`.cancel` role) and "Merge" (`.destructive` role)

### Methods

| Method | Signature | Purpose |
|--------|-----------|---------|
| `toggleSet` | `toggleSet<T: Hashable>(_ set: inout Set<T>, _ value: T)` | Generic helper to insert/remove from a set |
| `statusColor` | `statusColor(_ status: String) -> Color` | Maps git status to color: M=orange, A=green, D=red, R=blue |
| `diffLineColor` | `diffLineColor(_ line: String) -> Color` | Maps diff line prefix to color: +=green, -=red, else secondary |
| `toggleInlineDiff` | `async toggleInlineDiff(key:workspace:filePath:)` | Expands/collapses inline diff for a file, lazily loading via `git diff -- filePath` |
| `loadAllDiffs` | `async loadAllDiffs()` | Iterates all `manager.workspaces`, loads diffs, stores results in `diffs` |
| `loadDiff` | `async loadDiff(for: Workspace) -> WorkspaceDiff?` | Runs `git -C {worktreePath} diff --numstat`, parses output into `DiffFile` array |
| `merge` | `async merge(_ diff: WorkspaceDiff)` | Runs `git -C {repoPath} merge {branch}`, then reloads all diffs |
| `runComparison` | `async runComparison()` | Runs `git -C {repoPath} diff {leftBranch} {rightBranch}`, stores output in `comparisonDiff` |

### Git Commands Used

| Command | Context |
|---------|---------|
| `git -C {worktreePath} diff --numstat` | Load file-level stats for a workspace |
| `git -C {worktreePath} diff -- {filePath}` | Load inline diff for a specific file |
| `git -C {worktreePath} diff` | Copy full patch to clipboard |
| `git -C {repoPath} merge {branch}` | Merge workspace branch into current branch |
| `git -C {repoPath} diff {leftBranch} {rightBranch}` | Compare two workspace branches |

### Computed Properties

- `allExtensions: [String]` -- Unique, sorted file extensions extracted from all `diffs` files
- `filteredDiffs: [WorkspaceDiff]` -- Applies workspace filter, status filter, and extension filter, recalculates addition/deletion totals per workspace, removes workspaces with no matching files

## Design Consistency

| Element | Font | Color | Spacing |
|---------|------|-------|---------|
| Window title | `.system(size: 14, weight: .semibold)` | Primary | padding 12 |
| Branch name | `.system(size: 10, design: .monospaced)` | `.secondary` | -- |
| File path | `.system(size: 11, design: .monospaced)` | Primary | padding horizontal 12, vertical 2 |
| Diff lines | `.system(size: 9, design: .monospaced)` | Green/Red/Secondary | -- |
| Status badge | `.system(size: 9, weight: .bold, design: .monospaced)` | Status-specific color | frame width 12 |
| Action icons | `.system(size: 9)` | `.secondary` | -- |
| Filter labels | `.system(size: 10)` | -- | padding horizontal 12, vertical 6 |
| Window frame | -- | `Color(nsColor: .windowBackgroundColor)` | 640 x 500 |
| Section header bg | -- | `Color.primary.opacity(0.03)` | padding horizontal 12, vertical 8 |
| Diff block bg | -- | `Color.primary.opacity(0.02)` | padding 6, cornerRadius 4 |

## Ghostty Codebase Alignment

### Types Used
- `Workspace` from `WorkspaceModel.swift` (id, name, branch, worktreePath, repoPath, agent)
- `WorktreeManager` from `WorktreeManager.swift` (workspaces array)
- `AgentType` from `AgentType.swift` (iconName property)
- `AgentColors` from Agent feature (color(for:) static method)
- `GitShell` from Git feature (asyncOutput static method)

### Integration Points
- Receives `WorktreeManager` as `@ObservedObject` from parent view
- Uses `@Environment(\.dismiss)` for sheet dismissal
- Launched via `.task` modifier on appear
- Merge alert uses SwiftUI `.alert` modifier with `isPresented` binding

## Known Issues

1. **All files show status "M"**: `loadDiff(for:)` parses `git diff --numstat` which does not include file status. Every file is hardcoded as `status: "M"`. To fix, should also run `git diff --name-status` and merge results.
2. **Merge targets current branch, not main**: `merge(_:)` runs `git merge {branch}` in `repoPath` which merges into whatever branch is currently checked out, not necessarily main.
3. **No error handling for git commands**: All `GitShell.asyncOutput` calls silently return nil on failure with no user feedback.
4. **Inline diff cache not invalidated**: `inlineDiffs` dictionary is never cleared when refreshing, so stale diffs may be shown after changes.
5. **Sequential workspace loading**: `loadAllDiffs()` iterates workspaces sequentially rather than concurrently, which is slow for many workspaces.
6. **Comparison section has no loading indicator**: `runComparison()` can take time but shows no progress.
7. **No pagination for large diffs**: `diffBlock` truncates at 80 lines with no "show more" option.

## Future Enhancements

- Fix file status detection by combining `--numstat` with `--name-status` output
- Add concurrent workspace diff loading with `TaskGroup`
- Add "show more" for truncated inline diffs
- Add staging/unstaging individual files
- Add cherry-pick support between workspaces
- Add diff statistics summary (total files, additions, deletions across all workspaces)
- Add search within diff content
- Support three-way merge conflict visualization

## Changelog

- 2026-03-20: Initial spec
