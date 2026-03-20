# Workspace Cards (Row)

## Overview

`WorkspaceRow` is the primary visual representation of a single workspace in the Ghostset sidebar. It renders as a compact horizontal card containing an agent icon, workspace name with optional pin indicator, an abbreviated branch name, up to three color-coded tag pills with an overflow counter, a pulsing status dot (with unread override), and live git change statistics (additions/deletions). The row is designed for a dark, minimal aesthetic and loads its git stats asynchronously via the `GitShell` helper. Archived workspaces render at 50% opacity, and a native tooltip surfaces branch, change stats, and status on hover.

## Architecture

### Key Files

| File | Path | Role |
|------|------|------|
| **WorkspaceRow.swift** | `Sources/Features/Workspace/WorkspaceRow.swift` | The view itself (164 lines) |
| **WorkspaceModel.swift** | `Sources/Features/Workspace/WorkspaceModel.swift` | `Workspace` struct, `WorkspaceStatus` enum, `WorkspaceChangeStats` struct |
| **TagDefinition.swift** | `Sources/Features/Workspace/TagDefinition.swift` | `TagDefinition` struct with color resolution and preset tags |
| **WorkspaceHelpers.swift** | `Sources/Features/Workspace/WorkspaceHelpers.swift` | `AgentColors` enum, `GitShell` enum (sync/async git commands), `FuzzyMatch` |
| **AgentType.swift** | `Sources/Features/Agent/AgentType.swift` | `AgentType` enum (`.claude`, `.codex`, `.copilot`, `.opencode`, `.gemini`, `.cursor`, `.custom(String)`) |

### Data Models

| Type | Kind | Key Fields |
|------|------|------------|
| `Workspace` | `struct` (Identifiable, Codable, Hashable) | `id: UUID`, `name: String`, `repoPath: String`, `worktreePath: String`, `branch: String`, `createdAt: Date`, `agent: AgentType?`, `status: WorkspaceStatus`, `tags: [String]`, `taskDescription: String?`, `isPinned: Bool`, `isArchived: Bool`, `sortOrder: Int` |
| `WorkspaceStatus` | `enum` (Codable, Equatable) | Cases: `.creating`, `.ready`, `.running(pid: Int32)`, `.stopped`, `.error(String)` |
| `WorkspaceChangeStats` | `struct` (Equatable) | `additions: Int`, `deletions: Int`, `filesChanged: Int`; static `.zero` sentinel |
| `TagDefinition` | `struct` (Codable, Identifiable, Hashable) | `name: String`, `colorName: String`, `iconName: String?`, `parentTag: String?`; computed `color: Color`, `displayName: String` |
| `AgentType` | `enum` | Cases: `.claude`, `.codex`, `.copilot`, `.opencode`, `.gemini`, `.cursor`, `.custom(String)` |

### Feature Connections

- **WorkspaceSidebar** renders a `List` of `WorkspaceRow` views, passing each workspace and a `tagLookup` closure.
- **WorktreeManager** owns the `[Workspace]` array and provides mutation methods (immutable copy-on-write pattern).
- **GitShell.asyncOutput** is called from the `.task(id:)` modifier to fetch `git diff --shortstat` output for the workspace's worktree path.
- **AgentColors.color(for:)** centralizes agent-to-color mapping, used here for the agent icon tint.
- **TagDefinition** is resolved via the `tagLookup: (String) -> TagDefinition` closure, decoupling the row from the tag registry.

## Current Implementation

### Input Properties

| Property | Type | Kind | Purpose |
|----------|------|------|---------|
| `workspace` | `Workspace` | `let` (injected) | The workspace data to display |
| `tagLookup` | `(String) -> TagDefinition` | `let` (closure) | Resolves a tag name string to its `TagDefinition` for color/icon lookup |
| `hasUnread` | `Bool` | `var` (default `false`) | Whether this workspace has unread activity; overrides status dot color to orange and triggers pulse animation |

### State Properties

| Property | Type | Initial Value | Purpose |
|----------|------|---------------|---------|
| `changeStats` | `WorkspaceChangeStats` | `.zero` | Stores parsed `git diff --shortstat` results (additions, deletions, filesChanged) |
| `isAnimatingStatus` | `Bool` | `false` | Controls the pulsing scale animation on the status dot |

### Visual Elements (Left to Right)

#### 1. Agent Icon (leftmost)

- **Container**: `Group` wrapped in `.frame(width: 14)` for fixed alignment.
- **With agent**: `Image(systemName: agent.iconName)` — each `AgentType` case provides its own SF Symbol name.
  - Font: `.system(size: 11)`
  - Color: `AgentColors.color(for: agent).opacity(0.9)`
  - Agent color mapping: `.claude` = `.orange`, `.codex` = `.green`, `.copilot` = `.indigo`, `.opencode` = `.teal`, `.gemini` = `.blue`, `.cursor` = `.purple`, `.custom` = `.secondary`
- **Without agent**: `Image(systemName: "terminal")`
  - Font: `.system(size: 11)`
  - Color: `.secondary`

#### 2. Name + Branch + Tags (center, vertically stacked)

Wrapped in `VStack(alignment: .leading, spacing: 2)`.

##### 2a. Name Row

`HStack(spacing: 4)`:

- **Pin indicator** (conditional: only when `workspace.isPinned == true`):
  - `Image(systemName: "pin.fill")`
  - Font: `.system(size: 8)`
  - Color: `.orange.opacity(0.7)`
- **Workspace name**:
  - `Text(workspace.name)`
  - Font: `.system(size: 13, weight: .medium)`
  - Line limit: 1 (truncates with ellipsis)

##### 2b. Branch Label (conditional)

Only displayed when `abbreviatedBranch != workspace.name`. The `abbreviatedBranch` computed property strips the `"ghostset/"` prefix from the branch name if present.

- `Text(abbreviatedBranch)`
- Font: `.system(size: 10, design: .monospaced)`
- Color: `.secondary` (via `.foregroundStyle`)
- Line limit: 1

##### 2c. Tag Pills (conditional)

Only displayed when `workspace.tags` is non-empty. Wrapped in `HStack(spacing: 4)` with `.padding(.top, 1)`.

- **Displayed tags**: Up to 3 tags shown via `ForEach(workspace.tags.prefix(3), id: \.self)`.
- **Each tag pill** (`tagPill(_ name:)` function):
  - Resolves color via `tagLookup(name)` returning a `TagDefinition`.
  - `Text(name)` with:
    - Font: `.system(size: 9, weight: .medium)`
    - `.fixedSize()` — prevents compression
    - Text color: `def.color.opacity(0.9)`
    - Horizontal padding: 6pt
    - Vertical padding: 2pt
    - Background: `def.color.opacity(0.18)` (subtle tinted fill)
    - Shape: `Capsule()` (via `.clipShape`)
    - Border: `Capsule().strokeBorder(def.color.opacity(0.25), lineWidth: 0.5)` (hairline tinted stroke)
- **Overflow counter** (conditional: when `workspace.tags.count > 3`):
  - `Text("+\(workspace.tags.count - 3)")`
  - Font: `.system(size: 8)`
  - Color: `.tertiary` (via `.foregroundStyle`)

#### 3. Spacer

`Spacer(minLength: 4)` — pushes right-side content to the trailing edge.

#### 4. Status + Stats (rightmost, vertically stacked)

Wrapped in `VStack(alignment: .trailing, spacing: 3)`.

##### 4a. Status Dot

- `Circle().fill(...)` — filled circle indicator.
- Size: `.frame(width: 6, height: 6)`
- Color logic:
  - If `hasUnread == true`: `Color.orange`
  - Otherwise: `statusColor` computed property based on `workspace.status`:
    - `.creating` = `.secondary`
    - `.ready` = `.blue`
    - `.running` = `.green`
    - `.stopped` = `.gray`
    - `.error` = `.red`
- **Pulse animation**:
  - `.scaleEffect(isAnimatingStatus ? 1.5 : 1.0)` — scales up 50% when animating
  - Animation: `.easeInOut(duration: 0.6).repeatForever(autoreverses: true)` when `isAnimatingStatus` is true; `.default` otherwise
  - Bound to `isAnimatingStatus` value changes

##### 4b. Change Stats (conditional)

Only displayed when `changeStats != .zero`.

`HStack(spacing: 2)`:

- **Additions** (conditional: `changeStats.additions > 0`):
  - `Text("+\(changeStats.additions)")`
  - Color: `.green.opacity(0.8)`
- **Deletions** (conditional: `changeStats.deletions > 0`):
  - `Text("-\(changeStats.deletions)")`
  - Color: `.red.opacity(0.8)`
- Font (applied to HStack): `.system(size: 9, design: .monospaced)`

### Container Modifiers (applied to outer HStack)

| Modifier | Value | Purpose |
|----------|-------|---------|
| `HStack` spacing | `10` | Horizontal gap between agent icon, center content, and status |
| `HStack` alignment | `.center` | Vertical centering of all elements |
| `.padding(.vertical, 6)` | 6pt top and bottom | Row breathing room |
| `.opacity(...)` | `0.5` if `workspace.isArchived`, else `1.0` | Dims archived workspaces |
| `.help(hoverTooltip)` | Multi-line string | Native macOS tooltip on hover |
| `.task(id: workspace.id)` | Async task | Calls `loadChangeStats()` when view appears or workspace ID changes |
| `.onChange(of: hasUnread)` | Closure | Sets `isAnimatingStatus = newValue` to start/stop pulse |

### Hover Tooltip (`hoverTooltip` computed property)

Multi-line string built from:
1. `"Branch: \(workspace.branch)"` — always present
2. `"\(changeStats.filesChanged) files, +\(changeStats.additions) -\(changeStats.deletions)"` — only if `changeStats != .zero`
3. `"Status: \(workspace.status.displayLabel)"` — always present (e.g., "Creating...", "Ready", "Running", "Stopped", "Error: ...")

Lines joined with `"\n"`.

### Async Data Loading (`loadChangeStats()`)

1. Reads `workspace.worktreePath`.
2. Guards that the path exists on disk via `FileManager.default.fileExists(atPath:)`.
3. Calls `GitShell.asyncOutput(["git", "-C", worktreePath, "diff", "--shortstat"])` — runs git on a background queue via `DispatchQueue.global(qos: .userInitiated)`.
4. Parses stdout with `GitShell.parseShortstat(_:)` which extracts file count, insertions, and deletions from the standard `--shortstat` format.
5. Assigns result to `@State changeStats`, triggering a view update.

## Design Consistency

### Font Scale

| Element | Size | Weight | Design | Usage |
|---------|------|--------|--------|-------|
| Workspace name | 13pt | `.medium` | default | Primary label |
| Agent icon | 11pt | regular | default | SF Symbol sizing |
| Branch name | 10pt | regular | `.monospaced` | Secondary label, code-style |
| Tag pill text | 9pt | `.medium` | default | Tertiary label |
| Change stats | 9pt | regular | `.monospaced` | Numerical data |
| Pin icon | 8pt | regular | default | Micro indicator |
| Overflow counter | 8pt | regular | default | Micro indicator |

### Spacing

| Context | Value |
|---------|-------|
| Outer HStack spacing | 10pt |
| Name row HStack spacing | 4pt |
| Center VStack spacing | 2pt |
| Tag HStack spacing | 4pt |
| Status VStack spacing | 3pt |
| Change stats HStack spacing | 2pt |
| Vertical padding (row) | 6pt |
| Tag pill horizontal padding | 6pt |
| Tag pill vertical padding | 2pt |
| Tags top padding | 1pt |
| Spacer minimum length | 4pt |

### Color Palette

| Element | Color | Opacity |
|---------|-------|---------|
| Pin icon | `.orange` | `0.7` |
| Agent icon (with agent) | varies by `AgentColors` | `0.9` |
| Agent icon (no agent) | `.secondary` | `1.0` |
| Branch text | `.secondary` | `1.0` |
| Tag pill text | tag's `def.color` | `0.9` |
| Tag pill background | tag's `def.color` | `0.18` |
| Tag pill border | tag's `def.color` | `0.25` |
| Tag overflow text | `.tertiary` | `1.0` |
| Status dot (unread) | `.orange` | `1.0` |
| Status dot (creating) | `.secondary` | `1.0` |
| Status dot (ready) | `.blue` | `1.0` |
| Status dot (running) | `.green` | `1.0` |
| Status dot (stopped) | `.gray` | `1.0` |
| Status dot (error) | `.red` | `1.0` |
| Additions text | `.green` | `0.8` |
| Deletions text | `.red` | `0.8` |
| Archived row | inherited | `0.5` (full row) |

### SwiftUI Patterns

- **Composition via computed properties**: `agentIcon`, `abbreviatedBranch`, `statusColor`, `hoverTooltip` are all private computed properties, keeping `body` readable.
- **Extracted subview function**: `tagPill(_:)` is a `@ViewBuilder`-style function returning `some View`.
- **Async loading via `.task(id:)`**: Re-triggers when `workspace.id` changes, avoiding manual lifecycle management.
- **Animation binding via `.onChange(of:)`**: Bridges external `hasUnread` changes to internal `isAnimatingStatus` state.
- **Conditional rendering**: Branch, tags, change stats, pin icon all use `if` guards rather than opacity tricks — elements are absent from the view tree when not needed.
- **Closure injection**: `tagLookup` decouples the row from any specific tag storage mechanism.

## Ghostty Codebase Alignment

### Types Used from Ghostset Layer

| Type | Source File | Usage in WorkspaceRow |
|------|------------|----------------------|
| `Workspace` | `WorkspaceModel.swift` | Primary data input |
| `WorkspaceStatus` | `WorkspaceModel.swift` | Status dot color and tooltip label |
| `WorkspaceChangeStats` | `WorkspaceModel.swift` | Git diff statistics display |
| `AgentType` | `AgentType.swift` | Agent icon name resolution |
| `AgentColors` | `WorkspaceHelpers.swift` | Agent icon color resolution |
| `TagDefinition` | `TagDefinition.swift` | Tag pill color resolution via `tagLookup` closure |
| `GitShell` | `WorkspaceHelpers.swift` | Async git diff stat loading and parsing |

### Integration Points

1. **WorkspaceSidebar.swift** — instantiates `WorkspaceRow` for each workspace in the sidebar list, passing `workspace`, `tagLookup`, and `hasUnread` values.
2. **WorktreeManager** — provides the `[Workspace]` array and the tag registry used to construct the `tagLookup` closure.
3. **File system** — `loadChangeStats()` directly checks `FileManager.default.fileExists(atPath:)` for the worktree path before invoking git.
4. **Git CLI** — `GitShell.asyncOutput` spawns `/usr/bin/git` as a `Process` on `DispatchQueue.global(qos: .userInitiated)`.

## Known Issues

### 1. Stale change stats after workspace mutations

`loadChangeStats()` is triggered by `.task(id: workspace.id)`, which only re-fires when the workspace's UUID changes. If files are modified within the worktree after the initial load, the stats remain stale until the view is recreated. There is no periodic refresh or notification-based invalidation.

### 2. Animation state not reset when `hasUnread` becomes false externally before `.onChange` fires

The `.onChange(of: hasUnread)` modifier sets `isAnimatingStatus = newValue`. However, if the view is recreated (e.g., due to list identity change) while `hasUnread` is false, `isAnimatingStatus` correctly defaults to `false`. The concern is narrow: if `hasUnread` is `true` at init time, the animation will NOT start because `.onChange` only fires on *changes*, not on initial value. The `@State private var isAnimatingStatus = false` will remain `false` even though `hasUnread` is `true`.

### 3. Branch abbreviation only strips one prefix

`abbreviatedBranch` only strips the `"ghostset/"` prefix. Other common prefixes (`feature/`, `bugfix/`, etc.) are displayed in full, which may cause truncation in narrow sidebars.

### 4. Tag pill `fixedSize()` can overflow

Each tag pill uses `.fixedSize()`, which prevents the text from being compressed. Combined with `ForEach(workspace.tags.prefix(3))`, three long tag names could overflow the available horizontal space, pushing the status column off-screen.

### 5. Git process not cancelled on view disappear

`loadChangeStats()` uses `GitShell.asyncOutput` which wraps a synchronous `Process` in `withCheckedContinuation`. If the view disappears (e.g., workspace deleted while git is running), the task is cancelled at the Swift concurrency level but the underlying `Process` continues to run until completion. This is a minor resource leak.

### 6. Potential main-thread state mutation from background

`GitShell.asyncOutput` resumes its continuation on a background queue (`DispatchQueue.global`). The `@State` assignment `changeStats = GitShell.parseShortstat(output)` happens after the `await`, which may or may not be on the main actor depending on Swift's actor inference for the `body` context. This could cause a main-thread assertion in debug builds.

## Future Enhancements

1. **Periodic refresh of change stats** — Use a `Timer` or `AsyncStream` to re-poll `git diff --shortstat` every N seconds while the workspace is visible.
2. **Tap-to-expand detail row** — Show `taskDescription`, full tag list, and file-level diff summary in an expandable disclosure area.
3. **Drag-and-drop reordering** — Enable manual sort order by supporting `onMove` or `draggable`/`dropDestination` modifiers.
4. **Context menu** — Right-click to pin, archive, rename, copy branch name, or open in Finder.
5. **Accessibility labels** — Add `.accessibilityLabel` and `.accessibilityValue` for VoiceOver support (currently absent).
6. **Last activity timestamp** — Show relative time ("2m ago") for the most recent git commit or terminal output.
7. **Agent status integration** — Show whether the agent process is actually running vs. the workspace status, with distinct indicators.
8. **Swipe actions** — Add leading/trailing swipe gestures for quick pin/archive on trackpad.
9. **Fix `hasUnread` initialization** — Use `.onAppear` or `.task` to sync `isAnimatingStatus` with the initial `hasUnread` value.
10. **Cancel git process on disappear** — Store the `Process` reference and call `terminate()` when the task is cancelled.

## Changelog

- **2026-03-20**: Initial spec. Documented all visual elements, state properties, color values, font sizes, spacing, integration points, and 6 known issues from code analysis of `WorkspaceRow.swift` (164 lines).
