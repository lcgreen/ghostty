# Git Status Panel

## Overview

The Git Status Panel (`GitStatusPanel`) is a VS Code-style source control panel embedded in the workspace sidebar of Ghostty's Ghostset workspace layer. It provides an inline interface for viewing changed files in a git worktree, staging and unstaging individual files or all files at once, composing and executing commits, and pushing to the remote. The panel renders directly below the workspace list inside `WorkspaceSidebar` and is toggled via a branch icon button or the `ghostset.toggleGitPanel` notification. It operates against the `worktreePath` of the currently selected `Workspace` struct, running git commands asynchronously through `Process` invocations on a background dispatch queue.

## Architecture

### Key Files

| File | Purpose |
|------|---------|
| `Sources/Features/Workspace/GitStatusPanel.swift` | Full implementation: view, data models, git shell integration |
| `Sources/Features/Workspace/WorkspaceSidebar.swift` | Host view — renders `GitStatusPanel` when `showingGitPanel` is true and a workspace is selected |
| `Sources/Features/Workspace/WorkspaceModel.swift` | Defines `Workspace` struct including `worktreePath` used by all git commands |
| `Sources/Features/Workspace/WorktreeManager.swift` | Creates/deletes worktrees that GitStatusPanel operates on |
| `Sources/Features/Git/GitService.swift` | Actor-based git service (separate from GitStatusPanel's own shell layer) |

### Data Models

#### `GitFileChange` (struct, `Identifiable`)

| Property | Type | Description |
|----------|------|-------------|
| `path` | `String` | Relative file path from repo root |
| `status` | `GitFileStatus` | Enum classifying the change type |
| `isStaged` | `Bool` (var) | Whether the file is in the staging area |
| `additions` | `Int` (var, default 0) | Number of added lines from `--numstat` |
| `deletions` | `Int` (var, default 0) | Number of deleted lines from `--numstat` |
| `id` | `String` (computed) | Returns `path` |
| `filename` | `String` (computed) | Last path component extracted via `URL(fileURLWithPath:).lastPathComponent` |

#### `GitFileStatus` (enum)

Each case has three computed properties — `symbol`, `iconName`, and `color`:

| Case | Symbol | SF Symbol Icon | Color |
|------|--------|---------------|-------|
| `.modified` | `M` | `square.fill` | `.orange` |
| `.added` | `A` | `plus.square.fill` | `.green` |
| `.deleted` | `D` | `minus.square.fill` | `.red` |
| `.renamed` | `R` | `arrow.right.square.fill` | `.blue` |
| `.untracked` | `?` | `plus.square` (outline, not filled) | `.green` |
| `.conflicted` | `U` | `exclamationmark.square.fill` | `.red` |

**Parsing logic** (`GitFileStatus.from(_ s: String) -> GitFileStatus`): Checks the first two characters of `git status --porcelain` output using `contains`. Priority order: `M` -> `A` -> `D` -> `R` -> `U` -> default `.untracked`.

### Feature Connections

- **Toggle mechanism**: The panel is toggled in `WorkspaceSidebar` via `@State private var showingGitPanel = false`. Two triggers exist:
  1. A branch icon button (`arrow.triangle.branch`) in the sidebar toolbar (line ~206 of WorkspaceSidebar.swift).
  2. A NotificationCenter listener for `Notification.Name("ghostset.toggleGitPanel")`.
- **Workspace binding**: `GitStatusPanel` receives a `Workspace` value type. The panel uses `workspace.worktreePath` for all git operations. The `.task(id: workspace.id)` modifier reloads data when the selected workspace changes.
- **Auto-refresh**: The panel subscribes to `NSApplication.didBecomeActiveNotification` to reload git status whenever the app regains focus (e.g., after switching from an editor).
- **Related views**: `WorkspaceDiffView` provides a separate diff viewing experience and also runs `git diff` against `workspace.worktreePath`. `WorkspaceRow` displays a compact `--shortstat` summary. These are independent of GitStatusPanel.

## Current Implementation

### State Properties

| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `changedFiles` | `[GitFileChange]` | `[]` | All changed files from porcelain output |
| `isLoading` | `Bool` | `false` | Controls loading spinner display |
| `commitMessage` | `String` | `""` | Bound to commit text field |
| `stagedExpanded` | `Bool` | `true` | Section expand state (declared but not used in body — see Known Issues) |
| `unstagedExpanded` | `Bool` | `true` | Section expand state (declared but not used in body — see Known Issues) |
| `branchName` | `String` | `""` | Current branch name (loaded but not displayed — see Known Issues) |
| `ahead` | `Int` | `0` | Commits ahead of upstream (loaded but not displayed) |
| `behind` | `Int` | `0` | Commits behind upstream (loaded but not displayed) |

### Commit Input (`commitInput`)

A horizontal stack containing:

1. **TextField** — Plain style, 11pt system font, placeholder "Commit message", bound to `$commitMessage`. Background is `Color.primary.opacity(0.04)` with 4pt corner radius. Padding: 8pt horizontal, 5pt vertical.
2. **Commit button** — Conditionally shown when `commitMessage` is non-empty AND `stagedFiles` is non-empty. Displays a green checkmark icon (`checkmark`, 9pt semibold). Triggers `commit()` async.
3. **Push button** — Always visible. Displays an upward arrow (`arrow.up`, 9pt semibold, secondary foreground). Triggers `push()` async.

The entire input area has 8pt horizontal padding and 4pt vertical padding.

### Push Button

Always visible in the commit input bar. Uses `arrow.up` SF Symbol at 9pt semibold with `.secondary` foreground style. Executes `push()` which runs `git push` with no additional flags (no `--set-upstream`, no force). No loading indicator or success/failure feedback is shown.

### Staged/Unstaged Sections (`sectionView`)

A reusable section builder is defined but **not currently used in the body**. The body instead renders a flat `ForEach(changedFiles)` list. The `sectionView` function accepts:

- `title: String` — Section header text
- `count: Int` — File count badge
- `files: [GitFileChange]` — Files to display
- `isExpanded: Binding<Bool>` — Collapse/expand toggle
- `stageAction: @escaping () async -> Void` — Stage/unstage all action
- `stageIcon: String` — SF Symbol for the stage-all button
- `fileAction: @escaping (GitFileChange) async -> Void` — Per-file action

Section header layout:
- Chevron toggle (`chevron.down` / `chevron.right`, 8pt semibold, tertiary, 10pt wide frame)
- Title text (11pt semibold, secondary)
- Count badge (10pt, tertiary)
- Spacer
- Stage/unstage-all button (9pt medium, secondary, 16x16 frame)
- Refresh button (`arrow.clockwise`, 9pt, tertiary, 16x16 frame) — triggers `loadAll()`

Expand/collapse uses `withAnimation(.easeInOut(duration: 0.15))`.

### File Rows (`fileRow`)

Each file row is a horizontal stack:

1. **Status icon** — `file.status.iconName` SF Symbol, 8pt font, colored by `file.status.color`, 10pt wide frame.
2. **File path** — `file.path` in 10pt monospaced font, single line, truncation mode `.head` (truncates from the beginning to keep the filename visible).
3. **Spacer** — minimum length 2pt.
4. **Additions count** — Shown if `file.additions > 0`. Green text `+N` in 8pt monospaced.
5. **Deletions count** — Shown if `file.deletions > 0`. Red text `-N` in 8pt monospaced.
6. **Stage/unstage button** — `plus` icon if unstaged, `minus` icon if staged. 7pt bold, tertiary foreground.

Row padding: 10pt horizontal, 1pt vertical. `contentShape(Rectangle())` ensures the entire row is tappable.

Clicking the stage/unstage button calls the provided `action` closure. In the body's `ForEach`, the action toggles: staged files call `unstage()`, unstaged files call `stage()`.

### Status Icons Reference

Complete icon and color mapping for file rows:

| Status | Icon (SF Symbol) | Color | Meaning |
|--------|-----------------|-------|---------|
| Modified | `square.fill` | Orange | Existing file with changes |
| Added | `plus.square.fill` | Green | New file tracked by git |
| Deleted | `minus.square.fill` | Red | File removed |
| Renamed | `arrow.right.square.fill` | Blue | File moved or renamed |
| Untracked | `plus.square` | Green | New file not yet tracked |
| Conflicted | `exclamationmark.square.fill` | Red | Merge conflict |

### Line Counts

Additions and deletions are sourced from `git diff --numstat` and displayed inline in each file row. The numstat output is parsed by splitting on tabs — format is `<additions>\t<deletions>\t<filepath>`. Counts of 0 are not displayed (the respective `Text` view is omitted entirely). Binary files may report `-` instead of numbers, which `Int(_:)` will parse as `nil`, defaulting to 0.

### Git Operations (Async Functions)

All operations run through `gitAsync(_ args: [String]) -> String?`, which:
1. Creates a `Process` with `/usr/bin/env` as the executable
2. Passes the full argument array (e.g., `["git", "-C", path, "status", "--porcelain"]`)
3. Runs on `DispatchQueue.global(qos: .userInitiated)`
4. Captures stdout via `Pipe`, discards stderr to `FileHandle.nullDevice`
5. Returns `nil` if the process exits with non-zero status or throws
6. Uses `withCheckedContinuation` to bridge from GCD to Swift concurrency

#### `loadAll()` — Full Refresh

- Sets `isLoading = true`, defers setting it back to `false`
- Validates `workspace.worktreePath` exists via `FileManager.default.fileExists(atPath:)`
- Launches two concurrent tasks via `async let`:
  - `loadStatus(path:)`
  - `loadBranch(path:)`
- Awaits both with `_ = await (statusTask, branchTask)`

#### `loadStatus(path:)` — File Status + Line Counts

Runs two git commands:

1. **`git -C <path> status --porcelain`**
   - Parses each line: first 2 characters are the status code, characters from index 3 onward are the file path
   - Staging detection: `isStaged = line.first != " " && line.first != "?"` — a file is considered staged if the first character of the porcelain output is neither a space nor `?`
   - Status character is the first 2 chars trimmed of whitespace, passed to `GitFileStatus.from(_:)`

2. **`git -C <path> diff --numstat`**
   - Parses tab-separated lines: `additions\tdeletions\tfilepath`
   - Builds a `[String: (adds: Int, dels: Int)]` dictionary keyed by file path
   - Note: This only captures unstaged diff stats. Staged file numstat would require `git diff --cached --numstat` (see Known Issues)

Combines both into `[GitFileChange]` and assigns to `changedFiles`.

#### `loadBranch(path:)` — Branch + Upstream Info

Runs two git commands:

1. **`git -C <path> rev-parse --abbrev-ref HEAD`**
   - Extracts current branch name, trims whitespace/newlines
   - Assigns to `branchName`

2. **`git -C <path> rev-list --count --left-right @{upstream}...HEAD`**
   - Parses tab-separated output: `<behind>\t<ahead>`
   - First value = commits behind upstream, last value = commits ahead
   - Assigns to `behind` and `ahead` respectively
   - Silently fails if no upstream is configured (gitAsync returns nil)

#### `stage(_ file:)` — Stage Single File

- **Command**: `git -C <worktreePath> add <file.path>`
- Reloads status after completion via `loadStatus(path:)`

#### `unstage(_ file:)` — Unstage Single File

- **Command**: `git -C <worktreePath> reset HEAD <file.path>`
- Reloads status after completion via `loadStatus(path:)`

#### `stageAll()` — Stage All Files

- **Command**: `git -C <worktreePath> add -A`
- The `-A` flag stages all changes including untracked and deleted files
- Reloads status after completion

#### `unstageAll()` — Unstage All Files

- **Command**: `git -C <worktreePath> reset HEAD`
- Reloads status after completion

#### `commit()` — Create Commit

- Captures `commitMessage` into local `msg` constant
- **Command**: `git -C <worktreePath> commit -m <msg>`
- Clears `commitMessage` to empty string after execution
- Reloads status after completion
- No validation beyond the UI guard (commit button hidden when message is empty or no staged files)

#### `push()` — Push to Remote

- **Command**: `git -C <worktreePath> push`
- No upstream tracking setup (`--set-upstream` not used)
- No status reload after push
- No success/error feedback to the user

### Loading State

Displayed when `isLoading == true`:
- `ProgressView()` with `.controlSize(.small)` (spinner)
- "Loading..." text in 10pt, tertiary foreground
- Centered horizontally with `maxWidth: .infinity`, minimum height 40pt

### Empty State

Displayed when `isLoading == false` and `changedFiles.isEmpty`:
- Green checkmark circle icon (`checkmark.circle`, 10pt, green at 0.6 opacity)
- "Working tree clean" text in 10pt, tertiary foreground
- Centered horizontally with `maxWidth: .infinity`, minimum height 36pt

### Helper Functions

#### `groupedByDir(_ files:)` — Directory Grouping

Groups `[GitFileChange]` by directory path. Returns `[(dir: String, files: [GitFileChange])]` sorted alphabetically by directory. This function is defined but **not currently called** in the view body (see Known Issues).

#### `directoryOf(_ path:)` — Extract Directory

Splits path by `/`, returns all components except the last joined by `/`. Returns `"."` for files in the root directory.

## Design Consistency

The panel follows Ghostset's sidebar design language:

- **Typography**: System font at 10-11pt for content, monospaced for file paths and line counts, matching other sidebar elements like `WorkspaceRow`.
- **Color system**: Uses SwiftUI semantic colors (`.primary`, `.secondary`, `.tertiary`) with explicit accent colors only for status semantics (green/red/orange/blue).
- **Iconography**: SF Symbols throughout, consistent with sidebar toolbar buttons. Size range 7-10pt matches the compact sidebar aesthetic.
- **Spacing**: Tight vertical spacing (1pt per file row, 4-5pt for headers) consistent with dense information display in other panels.
- **Interaction patterns**: `.buttonStyle(.plain)` for all buttons, no hover effects, consistent with sidebar toolbar style.
- **Animation**: 0.15s ease-in-out for section collapse, matching the workspace sidebar's expand/collapse animation timing.

## Ghostty Codebase Alignment

- **Workspace struct usage**: Correctly receives `Workspace` as a value type and reads `worktreePath` without mutation, following the immutability pattern documented in CLAUDE.md.
- **Shell execution**: Uses its own `gitAsync` helper via `Process` + `DispatchQueue.global` instead of the existing `GitService` actor or `GitShell.asyncOutput` utility used elsewhere (e.g., `WorkspaceDiffView`, `WorkspaceRow`). This is an inconsistency — see Known Issues.
- **Task lifecycle**: Uses `.task(id: workspace.id)` for data loading, which is the standard SwiftUI pattern used in other workspace views.
- **Notification-based communication**: Listens for `NSApplication.didBecomeActiveNotification`, consistent with other refresh mechanisms in the codebase.
- **No AppKit dependencies**: Pure SwiftUI implementation, consistent with other feature panels. Hosted inside `WorkspaceSidebar` which is itself SwiftUI.

## Known Issues

1. **Staged/Unstaged sections not rendered**: The view body renders a flat `ForEach(changedFiles)` list instead of using the `sectionView` builder with `stagedFiles`/`unstagedFiles` computed properties. The `sectionView` function, `stagedExpanded`/`unstagedExpanded` state, and `stageAll()`/`unstageAll()` methods are all defined but unreachable from the current body. This means users see all files in a single flat list without visual separation between staged and unstaged changes.

2. **Branch info loaded but not displayed**: `branchName`, `ahead`, and `behind` are loaded via `loadBranch(path:)` but never rendered in the view. The panel lacks a branch indicator or ahead/behind badge.

3. **Numstat only covers unstaged diffs**: `git diff --numstat` (without `--cached`) only reports line counts for unstaged changes. Staged files will show 0 additions and 0 deletions even if they have substantial changes. Should additionally run `git diff --cached --numstat` for staged file stats.

4. **Duplicate git shell layer**: `gitAsync` reimplements process execution instead of using `GitShell.asyncOutput` (used by `WorkspaceDiffView` and `WorkspaceRow`) or `GitService` (the actor-based service in `Sources/Features/Git/`). This creates maintenance burden and inconsistent error handling across the codebase.

5. **No error feedback**: All git operations silently discard errors (stderr goes to `FileHandle.nullDevice`, non-zero exit returns `nil`). Failed commits, pushes, or staging operations provide no user-visible feedback.

6. **Push has no safeguards**: `push()` runs `git push` unconditionally with no upstream check, no confirmation dialog, no progress indicator, and no success/failure notification. If no upstream is configured, the push silently fails.

7. **Staging detection heuristic**: The staging check `line.first != " " && line.first != "?"` is a simplification. In `git status --porcelain`, the first character is the index (staged) status and the second is the worktree status. A file can appear in both staged and unstaged states simultaneously (e.g., `MM` — modified, staged, then modified again). The current implementation would show it only once as staged, losing the unstaged modification.

8. **`isStaged` is mutable on a struct**: `GitFileChange.isStaged` is declared as `var`, which technically allows mutation. While no mutation occurs in practice (new arrays are always created), this violates the codebase's immutability principle. Should be `let`.

9. **No diff preview**: Clicking a file row does not open a diff view. The panel is view-only for file content — users must use `WorkspaceDiffView` separately.

10. **`groupedByDir` is dead code**: The directory grouping function and its helper `directoryOf` are defined but never called.

## Future Enhancements

- **Wire up staged/unstaged sections**: Use the existing `sectionView` builder to render `stagedFiles` and `unstagedFiles` as collapsible sections with stage-all/unstage-all buttons.
- **Display branch info**: Add a header showing `branchName` with ahead/behind badges using the already-loaded `ahead`/`behind` counts.
- **Inline diff preview**: Tapping a file row should present a diff view (potentially reusing `WorkspaceDiffView` or a sheet).
- **Consolidate git shell layer**: Migrate from the private `gitAsync` to `GitShell.asyncOutput` or `GitService` for consistency.
- **Error toasts**: Surface git operation failures via a transient notification banner or alert.
- **Pull support**: Add a pull button alongside push, with conflict detection.
- **Commit amend**: Support `--amend` via a toggle or long-press on the commit button.
- **Stash support**: Add stash/pop functionality for work-in-progress management.
- **Directory grouping**: Activate the existing `groupedByDir` function to visually group files by directory in each section.
- **Staged file numstat**: Run `git diff --cached --numstat` to show accurate line counts for staged files.
- **Push upstream setup**: Detect when no upstream exists and offer `git push --set-upstream origin <branch>`.

## Changelog

- **2026-03-20**: Initial spec created from `GitStatusPanel.swift` at commit `8aefb7f`. Documents full implementation including view hierarchy, data models, git commands, design patterns, known issues with unused code paths (sections, branch display, directory grouping), and future enhancement roadmap.
