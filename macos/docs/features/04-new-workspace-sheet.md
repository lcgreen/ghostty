# New Workspace Sheet

## Overview

`NewWorkspaceSheet` is the primary modal interface for creating Ghostset workspaces. It presents a compact, vertically stacked form (480pt wide, `.ultraThinMaterial` background with 10pt corner radius, 20pt outer padding) containing four major sections: a template bar for quick-start presets, a name row with live slug generation, a task section with agent picker and tag toggles, and a bottom bar housing the repo/branch pickers. On submission it delegates to `WorktreeManager.createWorkspace(repo:name:baseBranch:agent:tags:taskDescription:)` which creates a git worktree, persists state, and returns a `Workspace` value type. The sheet dismisses itself via `@Environment(\.dismiss)` and invokes the `onCreated` callback with the new workspace.

## Architecture

### Key Files

| File | Role |
|------|------|
| `Sources/Features/Workspace/NewWorkspaceSheet.swift` | The sheet view (527 lines, includes `FlowLayout`) |
| `Sources/Features/Workspace/WorkspaceModel.swift` | `Workspace` struct — UUID, name, repoPath, worktreePath, branch, agent, status, tags, taskDescription, isPinned, isArchived, sortOrder |
| `Sources/Features/Workspace/WorkspaceTemplate.swift` | `WorkspaceTemplate` struct + `TemplatePersistence` (JSON at `~/.ghostset/templates.json`) |
| `Sources/Features/Workspace/TagDefinition.swift` | Tag registry — preset tags, auto-tag keyword map, language detection, color palette |
| `Sources/Features/Workspace/WorkspaceHelpers.swift` | `GitShell` (sync git process runner) and `AgentColors` |
| `Sources/Features/Workspace/WorktreeManager.swift` | `ObservableObject` — owns `workspaces`, `tagDefinitions`, `templates`; calls `git worktree add` |
| `Sources/Features/Agent/AgentType.swift` | `AgentType` enum — `.claude`, `.codex`, `.copilot`, `.opencode`, `.gemini`, `.cursor`, `.custom(String)` |

### Data Models

**Workspace** (struct, Codable, Hashable):
- `id: UUID`, `name: String`, `repoPath: String`, `worktreePath: String`, `branch: String`, `createdAt: Date`
- `agent: AgentType?`, `status: WorkspaceStatus`, `tags: [String]`, `taskDescription: String?`
- `isPinned: Bool`, `isArchived: Bool`, `sortOrder: Int`

**WorkspaceTemplate** (struct, Codable, Identifiable):
- `id: UUID`, `name: String`, `repoPath: String?`, `baseBranch: String`, `agent: AgentType?`
- `tags: [String]`, `taskDescription: String?`, `environmentVariables: [String: String]`
- `setupCommand: String?`, `category: TemplateCategory`, `createdAt: Date`

**TemplateCategory** (enum, CaseIterable): `.aiAgents`, `.manual`, `.cicd`, `.custom`

**TagDefinition** (struct, Codable, Identifiable):
- `name: String`, `colorName: String`, `iconName: String?`, `parentTag: String?`
- Preset tags: `feature` (blue), `bugfix` (red), `refactor` (purple), `experiment` (orange), `review` (teal)
- Auto-tag keyword map: fix/bug/hotfix/patch -> bugfix; feat/feature/add/implement -> feature; refactor/cleanup/clean/reorganize -> refactor; experiment/spike/try/proto -> experiment; review/pr -> review

### Feature Connections

- **WorktreeManager** (`@ObservedObject var manager`): provides `workspaces`, `tagDefinitions`, `templates`, and the `createWorkspace()` async method.
- **Callback** (`let onCreated: (Workspace) -> Void`): invoked after successful creation; typically selects the new workspace in the sidebar.
- **UserDefaults**: recent repos stored under key `ghostset.recentRepos` (max 5 entries).
- **GitShell**: synchronous `/usr/bin/git` process execution for branch listing and worktree inspection.
- **NSOpenPanel**: used by `browseForRepo()` for directory selection.

## Current Implementation

### Initializer / Inputs

```swift
@ObservedObject var manager: WorktreeManager
let onCreated: (Workspace) -> Void
```

### @Environment Properties

| Property | Type | Purpose |
|----------|------|---------|
| `dismiss` | `DismissAction` | Dismisses the sheet after creation |
| `colorScheme` | `ColorScheme` | Available for theme-aware styling (currently unused in view body) |

### @State Properties (complete list)

| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `workspaceName` | `String` | `""` | User-entered workspace slug |
| `taskDescription` | `String` | `""` | Free-form task description |
| `selectedAgent` | `AgentType` | `.claude` | Currently selected AI agent |
| `selectedTags` | `Set<String>` | `[]` | Active tag names |
| `repoPath` | `String` | `""` | Absolute path to selected git repository |
| `baseBranch` | `String` | `"main"` | Branch to base the worktree on |
| `repoBranches` | `[String]` | `[]` | Branches discovered via `git branch` |
| `repoWorktreeBranches` | `Set<String>` | `[]` | Branches that already have worktrees |
| `branchSearch` | `String` | `""` | Search filter in branch picker popover |
| `newBranchName` | `String` | `""` | Name for creating a new branch |
| `showingBranchPicker` | `Bool` | `false` | Controls branch picker popover visibility |
| `showingClone` | `Bool` | `false` | Controls clone popover visibility |
| `showingEmpty` | `Bool` | `false` | Controls empty-repo popover visibility |
| `cloneURL` | `String` | `""` | URL entered in clone popover |
| `emptyRepoName` | `String` | `""` | Name entered in empty-repo popover |
| `newRepoLocation` | `String` | `~/.ghostset/projects` | Base directory for cloned/new repos |
| `isAddingRepo` | `Bool` | `false` | Guards against double-submission for clone/empty |
| `isCreating` | `Bool` | `false` | Guards the create-workspace button |
| `isCloning` | `Bool` | `false` | Shows progress indicator during clone |
| `errorMessage` | `String?` | `nil` | Displayed at bottom of sheet in red |
| `userToggledTags` | `Bool` | `false` | Once true, auto-tag inference from task text is disabled |

### Static Properties

| Property | Type | Value |
|----------|------|-------|
| `recentReposKey` | `String` | `"ghostset.recentRepos"` |
| `stopWords` | `Set<String>` | 20 common English words filtered from name suggestion |

### Body Layout (top to bottom)

```
VStack(spacing: 0) {
    templateBar          // horizontal scroll of template buttons
    Divider (opacity 0.2)
    nameRow              // workspace name text field + branch preview
    Divider (opacity 0.2)
    taskSection          // task description + agent picker + tags + submit
    Divider (opacity 0.2)
    bottomBar            // repo picker + branch picker + keyboard hint
    errorMessage?        // conditional red error text
}
.frame(width: 480)
.background(.ultraThinMaterial)
.cornerRadius(10)
.padding(20)
```

---

### Template Bar

**Location**: Top of sheet, above first divider.

**Layout**: `ScrollView(.horizontal, showsIndicators: false)` containing an `HStack(spacing: 6)` with `.padding(.horizontal, 12)` and `.padding(.vertical, 6)`.

**Data source**: `displayTemplates` computed property. Returns `manager.templates` if non-empty, otherwise falls back to `WorkspaceTemplate.presets`.

**Built-in presets** (from `WorkspaceTemplate.presets`):
1. **"Claude Feature"** — agent: `.claude`, tags: `["feature"]`, category: `.aiAgents`
2. **"Claude Bugfix"** — agent: `.claude`, tags: `["bugfix"]`, category: `.aiAgents`
3. **"Codex Auto"** — agent: `.codex`, tags: `["feature"]`, category: `.aiAgents`
4. **"Plain Shell"** — no agent, category: `.manual`

**Each template button**:
- `HStack(spacing: 4)` containing optional agent icon (`Image(systemName: agent.iconName)`, font size 8) and template name (`Text`, font size 10).
- Style: `.foregroundStyle(.secondary)`, `.padding(.horizontal, 8)`, `.padding(.vertical, 4)`, `Color.primary.opacity(0.04)` background, `cornerRadius(5)`.
- `buttonStyle(.plain)`.

**`applyTemplate(_:)` behavior**:
1. If template has an `agent`, sets `selectedAgent`.
2. If template has a non-empty `repoPath`, sets `repoPath` and calls `loadBranches(for:)`.
3. Sets `baseBranch` from template.
4. Sets `selectedTags` from template tags; sets `userToggledTags = true` if tags are non-empty.
5. If template has a `taskDescription`, sets `taskDescription`.

---

### Name Row

**Layout**: `HStack(spacing: 0)`.

**Left side — Text field with ghost suggestion**:
- `ZStack(alignment: .leading)`:
  - **Suggestion overlay**: Visible when `workspaceName` is empty AND `suggestedName` is non-empty. Shows `Text(suggestedName)` in font size 13, `.quaternary` foreground, with `.padding(.horizontal, 12)` and `.padding(.vertical, 8)`.
  - **TextField**: placeholder `"Workspace name"`, bound to `$workspaceName`, `.textFieldStyle(.plain)`, font size 13, same padding as suggestion.
  - **onChange handler**: Calls `sanitize(_:)` on every keystroke. Sanitization: lowercases input, replaces spaces with hyphens, strips all characters that are not letters, numbers, or hyphens.

**`suggestedName` computed property**: Takes `taskDescription`, lowercases it, splits on non-alphanumeric characters, filters out empty strings and stop words, takes the first 3 remaining words, joins with hyphens. Returns an empty string if no words remain.

**Right side**:
- `Spacer()`
- **Checkmark**: `Image(systemName: "checkmark.circle.fill")`, font size 10, green, `.padding(.trailing, 4)`. Only visible when `workspaceName` is non-empty.
- **Branch preview**: `Text("ghostset/\(workspaceName.isEmpty ? "name" : workspaceName)")`, font: system size 10, monospaced design, `.quaternary` foreground, `.padding(.trailing, 12)`.

---

### Task Section

**Layout**: `VStack(alignment: .leading, spacing: 6)`.

**Task description row** (`HStack(spacing: 4)`, `.padding(.horizontal, 12)`, `.padding(.top, 8)`):
- **TextField**: placeholder `"What do you want to do?"`, bound to `$taskDescription`, `axis: .vertical`, `.textFieldStyle(.plain)`, font size 13, `.lineLimit(1...4)` (expands to 4 lines).
- **onChange handler**: If `userToggledTags` is `false`, calls `TagDefinition.inferTags(from: newValue)` and sets `selectedTags` to the result. This provides live auto-tagging as the user types. Once the user manually toggles any tag, auto-inference is permanently disabled for that sheet session.
- **Checkmark**: Same as name row — green checkmark icon, font size 10, visible when `taskDescription` is non-empty.

**Controls row** (`HStack(spacing: 6)`, `.padding(.horizontal, 12)`, `.padding(.bottom, 8)`):
1. `agentPicker` — see Agent Picker section below.
2. `ScrollView(.horizontal, showsIndicators: false)` containing `HStack(spacing: 3)` of tag toggle buttons — see Tag Toggles section below.
3. `Spacer(minLength: 0)`
4. **Submit button**: `Image(systemName: "arrow.up.circle.fill")`, font size 20. Color is `.accentColor` when `isValid` is true, otherwise `Color.secondary.opacity(0.2)`. `buttonStyle(.plain)`, disabled when `!isValid || isCreating`. Has `.keyboardShortcut(.defaultAction)` (Enter/Return).

---

### Agent Picker

**Type**: `Menu` with `.menuStyle(.borderlessButton)` and `.fixedSize()`.

**Menu label** (`HStack(spacing: 3)`):
- Agent icon: `Image(systemName: selectedAgent.iconName)`, font size 9.
- Agent name: `Text(selectedAgent.displayName)`, font: system size 11, weight `.medium`.
- Chevron: `Image(systemName: "chevron.down")`, font size 7.
- Style: `.foregroundStyle(.primary)`, `.padding(.horizontal, 8)`, `.padding(.vertical, 4)`, `Color.secondary.opacity(0.08)` background, `cornerRadius(5)`.

**Menu items**:
- Iterates over `AgentType.builtIn`: `.claude`, `.codex`, `.copilot`, `.opencode`, `.gemini`.
- Each item: `Button` with `Label(agent.displayName, systemImage: agent.iconName)`.
- Below a `Divider()`: a `Button` labeled "None" with `systemImage: "terminal"`. Note: this button has an empty action `{ }` — it does not clear `selectedAgent`. This appears to be an incomplete implementation.

**Agent icon mappings**:
| Agent | SF Symbol | Display Name |
|-------|-----------|-------------|
| `.claude` | `sparkle` | `claude` |
| `.codex` | `chevron.left.forwardslash.chevron.right` | `codex` |
| `.copilot` | `person.badge.shield.checkmark` | `copilot` |
| `.opencode` | `square` | `opencode` |
| `.gemini` | `diamond` | `gemini` |
| `.cursor` | `cursorarrow.rays` | `cursor` |
| `.custom` | `terminal.fill` | (custom string) |

---

### Tag Toggles

**Rendering**: `ScrollView(.horizontal, showsIndicators: false)` containing `HStack(spacing: 3)`.

**Data source**: `manager.tagDefinitions` — an array of `TagDefinition` from `WorktreeManager`.

**Each tag toggle** (`tagToggle(_:)` function):
- A `Button` with `buttonStyle(.plain)`.
- **Action**: Sets `userToggledTags = true`. Toggles the tag name in/out of `selectedTags`.
- **Label**: `Text(def.name)` with:
  - Font: system size 9, weight `.semibold` when selected, `.regular` when not.
  - Foreground color: `def.color` when selected, `.secondary.opacity(0.6)` when not.
  - Padding: `.horizontal(6)`, `.vertical(2)`.
  - Background: `def.color.opacity(0.15)` when selected, `Color.clear` when not.
  - Shape: `Capsule()` clip.

**Auto-tag inference** (via `TagDefinition.inferTags(from:)`):
- Splits text on non-alphanumeric characters, lowercases.
- Looks up each word in `autoTagKeywords` dictionary.
- Returns sorted array of unique matching tag names.
- Example: typing "fix the login bug" would auto-select `bugfix` (matched by both "fix" and "bug").

---

### Bottom Bar

**Layout**: `HStack(spacing: 8)`, `.padding(.horizontal, 12)`, `.padding(.vertical, 5)`.

**Contents** (left to right):
1. `repoPicker` — repo selection menu.
2. `branchPicker` — branch selection button/popover.
3. `Spacer()`
4. Keyboard hint: `Text("\u{2318}\u{21A9}")` (displays "⌘↩"), font size 9, `.quaternary` foreground.

---

### Repo Picker

**Type**: `Menu` with `.menuStyle(.borderlessButton)` and `.fixedSize()`.

**Menu label** (`HStack(spacing: 4)`):
- Status indicator: `Circle().fill(repoIndicatorColor).frame(width: 5, height: 5)`.
  - `.empty` (no repo selected): `Color.secondary.opacity(0.3)` — gray dot.
  - `.valid` (path exists and is directory): `.green` — green dot.
  - `.invalid` (path set but not a valid directory): `.red` — red dot.
- Repo name: `Text(repoPath.isEmpty ? "repo" : repoDisplayName(repoPath))`, font size 10. `repoDisplayName` returns `URL(fileURLWithPath: path).lastPathComponent`.
- Chevron: `Image(systemName: "chevron.up.chevron.down")`, font size 7.
- Style: `.foregroundStyle(.secondary)`.

**Menu sections**:

1. **"Recent" section** (conditional — only if `loadRecentRepos()` returns non-empty):
   - Lists up to 5 recently used repos from `UserDefaults`.
   - Each button calls `repoPath = repo; loadBranches(for: repo)`.
   - Display name: last path component.

2. **"Repositories" section** (conditional — only repos not already in recent list):
   - Source: `availableRepos` — all unique `repoPath` values from `manager.workspaces`, sorted.
   - Each button: same behavior as recent repos.

3. **Divider**

4. **"Browse..."** button: Opens `NSOpenPanel` configured for directory-only selection (`canChooseFiles: false`, `canChooseDirectories: true`, `allowsMultipleSelection: false`, message: "Select a git repository"). On `.OK`, sets `repoPath` and calls `loadBranches(for:)`.

5. **"Clone..."** button: Resets `cloneURL` to empty, sets `showingClone = true`.

6. **"New Empty..."** button: Resets `emptyRepoName` to empty, sets `showingEmpty = true`.

**Attached popovers**: `.popover(isPresented: $showingClone)` and `.popover(isPresented: $showingEmpty)`.

#### Repo Validation

```swift
private enum RepoValidation { case empty, valid, invalid }
```

- `.empty`: `repoPath.isEmpty`
- `.valid`: Path exists AND is a directory (`FileManager.fileExists(atPath:isDirectory:)`)
- `.invalid`: Path is non-empty but does not exist or is not a directory

**Form validity** (`isValid` computed property): `!repoPath.isEmpty && repoValidation == .valid`. Note: a valid repo is the only hard requirement — workspace name and task description are both optional.

---

### Clone Popover

**Frame**: `width: 280`, `padding(10)`.

**Layout**: `VStack(alignment: .leading, spacing: 8)`.

**Contents**:
1. **Title**: `Text("Clone")`, font: system size 11, weight `.semibold`.
2. **URL field**: `TextField("https:// or git@...", text: $cloneURL)`, `.textFieldStyle(.roundedBorder)`, font: system size 11, monospaced design.
3. **Progress indicator** (conditional, shown when `isCloning`): `HStack(spacing: 6)` with `ProgressView().controlSize(.small)` and `Text("Cloning...")`, font size 11, `.secondary`.
4. **Button row** (`HStack`):
   - `Spacer()`
   - **Cancel button**: `buttonStyle(.plain)`, `.secondary`, font size 11. Sets `showingClone = false`.
   - **Clone button**: `buttonStyle(.borderedProminent)`, `.controlSize(.small)`. Disabled when `cloneURL.isEmpty || isAddingRepo || isCloning`. Calls `cloneRepo()`.

**`cloneRepo()` behavior**:
1. **URL validation**: Must start with `https://`, `http://`, `git@`, or `ssh://`. If invalid, sets `errorMessage` and returns.
2. Sets `isAddingRepo = true`, `isCloning = true`, clears `errorMessage`.
3. Derives repo name from URL: splits on `/`, takes last component, strips `.git` suffix. Falls back to `"project"`.
4. Destination: `"\(newRepoLocation)/\(name)"` — e.g., `~/.ghostset/projects/my-repo`.
5. Creates `newRepoLocation` directory with `createDirectory(withIntermediateDirectories: true)`.
6. Runs `Process` with `/usr/bin/git clone <url> <dest>`. stdout goes to `FileHandle.nullDevice`, stderr to a `Pipe()`.
7. On `terminationStatus == 0`: sets `repoPath = dest`, calls `loadBranches(for: dest)`, closes popover, resets flags.
8. On failure: sets `errorMessage = "Clone failed"`, resets flags.
9. On exception: sets `errorMessage` to `error.localizedDescription`, resets flags.

**Threading note**: The `Process` is run inside a `Task { }` block. `p.waitUntilExit()` blocks the Task's thread, which is a cooperative thread from the Swift concurrency pool. This is a potential issue — see Known Issues.

---

### Empty Repo Popover

**Frame**: `width: 240`, `padding(10)`.

**Layout**: `VStack(alignment: .leading, spacing: 8)`.

**Contents**:
1. **Title**: `Text("New Repository")`, font: system size 11, weight `.semibold`.
2. **Name field**: `TextField("my-project", text: $emptyRepoName)`, `.textFieldStyle(.roundedBorder)`, font size 11.
3. **Button row** (`HStack`):
   - `Spacer()`
   - **Cancel button**: same styling as clone popover. Sets `showingEmpty = false`.
   - **Create button**: `buttonStyle(.borderedProminent)`, `.controlSize(.small)`. Disabled when `emptyRepoName.isEmpty || isAddingRepo`. Calls `createEmptyRepo()`.

**`createEmptyRepo()` behavior**:
1. Sets `isAddingRepo = true`, clears `errorMessage`.
2. Destination: `"\(newRepoLocation)/\(emptyRepoName)"`.
3. Creates directory with `createDirectory(withIntermediateDirectories: true)`.
4. Runs `Process` with `/usr/bin/git init <dest>`. stdout goes to `FileHandle.nullDevice`.
5. On success: sets `repoPath`, loads branches, closes popover, resets flag.
6. On exception: sets error message, resets flag.

---

### Branch Picker

**Trigger**: `Button` with `buttonStyle(.plain)`.

**Button label** (`HStack(spacing: 3)`):
- Branch icon: `Image(systemName: "arrow.triangle.branch")`, font size 8.
- Branch name: `Text(baseBranch)`, font size 10.
- Chevron: `Image(systemName: "chevron.up.chevron.down")`, font size 7.
- Style: `.foregroundStyle(.secondary)`.

**Popover** (`.popover(isPresented: $showingBranchPicker)`):

**Frame**: `width: 220`.

**Layout**: `VStack(alignment: .leading, spacing: 0)`.

**Sections** (top to bottom):

#### 1. New Branch Section
- **Section label**: `sectionLabel("New Branch")` — `Text`, font size 8, weight `.semibold`, `.tertiary`, `.textCase(.uppercase)`, padding: `.horizontal(8)`, `.top(6)`, `.bottom(2)`.
- **Row** (`HStack(spacing: 4)`, padding: `.horizontal(8)`, `.vertical(6)`):
  - `TextField("branch-name", text: $newBranchName)`, `.textFieldStyle(.roundedBorder)`, font: system size 11, monospaced.
  - **Add button**: `Image(systemName: "plus.circle.fill")`, font size 14, `.accentColor`. `buttonStyle(.plain)`. Disabled when `newBranchName` (trimmed) is empty.
  - **Action**: Trims whitespace from `newBranchName`. If non-empty, sets `baseBranch = name`, clears `newBranchName`, closes popover.
  - Note: This does NOT create the git branch — it only sets the branch name. The actual branch is created later by `WorktreeManager.createWorkspace()` when it runs `git worktree add`.

#### 2. Search Section
- **Divider**
- **Row** (`HStack(spacing: 6)`, padding: `.horizontal(8)`, `.vertical(6)`):
  - Magnifying glass: `Image(systemName: "magnifyingglass")`, font size 9, `.tertiary`.
  - `TextField("Search", text: $branchSearch)`, `.textFieldStyle(.plain)`, font size 11.
  - Clear button (conditional, visible when `branchSearch` is non-empty): `Image(systemName: "xmark.circle.fill")`, font size 9, `.tertiary`. Clears `branchSearch`.

#### 3. Branch List
- **Divider**
- **Empty state** (when `repoBranches` is empty — no repo selected or repo has no branches):
  - Shows fallback list: `["main", "master", "develop"]` rendered via `branchRow(_:wt:)` with `wt: false`.
- **Populated state** (when `repoBranches` is non-empty):
  - `ScrollView` with `.frame(maxHeight: 220)`.
  - **Worktrees subsection** (conditional, shown if `filteredWorktreeBranches` is non-empty):
    - `sectionLabel("Worktrees")`
    - Each branch rendered via `branchRow(_:wt: true)`.
  - **Branches subsection** (conditional, shown if `filteredRegularBranches` is non-empty):
    - `sectionLabel("Branches")`
    - Each branch rendered via `branchRow(_:wt: false)`.
  - **No matches**: If both filtered lists are empty, shows `Text("No matches")`, font size 10, `.tertiary`, padding 8.

**`filteredWorktreeBranches`**: Filters `repoBranches` to only those in `repoWorktreeBranches`. Then applies `branchSearch` filter (case-insensitive contains).

**`filteredRegularBranches`**: Filters `repoBranches` to those NOT in `repoWorktreeBranches`. Then applies same search filter.

**`branchRow(_:wt:)`**:
- A `Button` with `buttonStyle(.plain)`.
- **Action**: Sets `baseBranch = branch`, clears `branchSearch`, closes popover.
- **Label** (`HStack(spacing: 5)`):
  - Worktree icon (conditional, `wt == true`): `Image(systemName: "arrow.triangle.branch")`, font size 8, `.tertiary`, frame width 10.
  - Branch name: `Text(branch)`, font size 11, `.lineLimit(1)`.
  - `Spacer()`
  - Checkmark (conditional, shown when `branch == baseBranch`): `Image(systemName: "checkmark")`, font: size 9, weight `.medium`, `.accentColor`.
- Padding: `.horizontal(8)`, `.vertical(4)`.
- Background: `Color.accentColor.opacity(0.08)` when selected, `Color.clear` when not.
- `.contentShape(Rectangle())` for full-row hit testing.

---

### Git Operations

#### `loadBranches(for:)`

Called when a repo is selected (from menu, browse panel, clone, or empty repo creation).

1. Resets `repoBranches`, `repoWorktreeBranches`, and `branchSearch` to empty.
2. Runs `git -C <repo> branch --format=%(refname:short)`:
   - Parses output: splits by newline, trims whitespace, filters empty strings, sorts.
   - Stores in `repoBranches`.
3. Runs `git -C <repo> worktree list --porcelain`:
   - Parses lines starting with `"branch refs/heads/"`.
   - Extracts branch names, stores in `repoWorktreeBranches` as a `Set<String>`.
4. Auto-selects `baseBranch`: prefers `"main"`, then `"master"`, then the first branch alphabetically.

#### `isValidGitURL(_:)` (static)

Returns `true` if trimmed URL starts with `https://`, `http://`, `git@`, or `ssh://`.

---

### Create Workspace Flow

**Trigger**: Submit button (arrow.up.circle.fill) or Enter key (`.keyboardShortcut(.defaultAction)`).

**`createWorkspace()` function**:

1. Guards on `isValid` (repo path must be set and valid directory).
2. Sets `isCreating = true`, clears `errorMessage`.
3. **Name resolution** (priority order):
   a. `workspaceName` if non-empty.
   b. `suggestedName` if non-empty (derived from task description).
   c. `sanitize(taskDescription.prefix(30))` — first 30 chars of task, sanitized.
   d. `"workspace-\(Int.random(in: 1000...9999))"` — random fallback.
4. Extracts `tags` as `Array(selectedTags)`.
5. Calls `Self.addRecentRepo(repoPath)` — adds to recent repos in UserDefaults (max 5, most recent first, deduped).
6. Enters `Task { }`:
   a. Trims whitespace/newlines from `taskDescription`.
   b. Calls `manager.createWorkspace(repo:name:baseBranch:agent:tags:taskDescription:)`.
   c. On success: calls `dismiss()`, then `onCreated(ws)`.
   d. On failure: sets `errorMessage`, resets `isCreating = false`.

---

### Error Display

Conditional `Text` at the bottom of the `VStack`:
- Font: system size 11.
- Color: `.red`.
- Padding: `.horizontal(12)`, `.bottom(4)`.
- Shows `errorMessage` when non-nil.

---

### FlowLayout (bonus utility)

`FlowLayout` is a custom SwiftUI `Layout` struct defined at the bottom of the file (lines 503-526). It implements a wrapping horizontal layout with configurable `spacing` (default 4pt).

- `sizeThatFits`: Calculates total size by simulating row-wrapping placement.
- `placeSubviews`: Places each subview at computed positions.
- Algorithm: Iterates subviews, placing each at `(x, y)`. When `x + subview.width > containerWidth` and `x > 0`, wraps to next row.

**Note**: `FlowLayout` is defined in this file but is not currently used by `NewWorkspaceSheet`. It may be used by other views that import this file, or it may be leftover from an earlier iteration.

## Design Consistency

### Font Sizes

| Element | Size | Weight | Design |
|---------|------|--------|--------|
| Template button text | 10 | regular | default |
| Template agent icon | 8 | regular | default |
| Workspace name field | 13 | regular | default |
| Suggested name overlay | 13 | regular | default |
| Name checkmark icon | 10 | regular | default |
| Branch preview text | 10 | regular | monospaced |
| Task description field | 13 | regular | default |
| Task checkmark icon | 10 | regular | default |
| Agent picker name | 11 | medium | default |
| Agent picker icon | 9 | regular | default |
| Agent picker chevron | 7 | regular | default |
| Tag toggle text | 9 | semibold/regular | default |
| Repo picker text | 10 | regular | default |
| Repo picker chevron | 7 | regular | default |
| Repo indicator dot | 5x5 | — | — |
| Branch picker text | 10 | regular | default |
| Branch picker icon | 8 | regular | default |
| Branch picker chevron | 7 | regular | default |
| Keyboard hint text | 9 | regular | default |
| Submit button icon | 20 | regular | default |
| Error message | 11 | regular | default |
| Section labels (popover) | 8 | semibold | default |
| Popover text fields | 11 | regular | monospaced (clone) / default (empty) |
| Popover titles | 11 | semibold | default |
| Branch row text | 11 | regular | default |
| Branch row checkmark | 9 | medium | default |
| New branch add icon | 14 | regular | default |
| Search magnifying glass | 9 | regular | default |
| Search clear button | 9 | regular | default |
| No matches text | 10 | regular | default |

### Spacing

| Context | Value |
|---------|-------|
| Main VStack | `spacing: 0` (dividers handle separation) |
| Template bar horizontal | `spacing: 6` between buttons |
| Template bar padding | `horizontal: 12`, `vertical: 6` |
| Name row | `spacing: 0` |
| Name row padding | `horizontal: 12`, `vertical: 8` |
| Task section VStack | `spacing: 6` |
| Task description padding | `horizontal: 12`, `top: 8` |
| Controls row | `spacing: 6`, padding: `horizontal: 12`, `bottom: 8` |
| Tag toggles | `spacing: 3` |
| Tag toggle internal padding | `horizontal: 6`, `vertical: 2` |
| Agent picker internal padding | `horizontal: 8`, `vertical: 4` |
| Bottom bar | `spacing: 8`, padding: `horizontal: 12`, `vertical: 5` |
| Clone popover | `padding: 10`, `spacing: 8` |
| Empty repo popover | `padding: 10`, `spacing: 8` |
| Branch picker popover sections | `horizontal: 8`, `top: 6`, `bottom: 2` |
| Branch row padding | `horizontal: 8`, `vertical: 4` |

### Colors

| Element | Color |
|---------|-------|
| Sheet background | `.ultraThinMaterial` |
| Dividers | `Divider().opacity(0.2)` |
| Template button background | `Color.primary.opacity(0.04)` |
| Template button text | `.secondary` |
| Agent picker background | `Color.secondary.opacity(0.08)` |
| Agent picker text | `.primary` |
| Suggested name text | `.quaternary` |
| Branch preview text | `.quaternary` |
| Keyboard hint | `.quaternary` |
| Repo/branch picker text | `.secondary` |
| Valid indicator | `.green` |
| Invalid indicator | `.red` |
| Empty indicator | `Color.secondary.opacity(0.3)` |
| Error message | `.red` |
| Selected tag background | `def.color.opacity(0.15)` |
| Unselected tag text | `.secondary.opacity(0.6)` |
| Selected branch row bg | `Color.accentColor.opacity(0.08)` |
| Submit enabled | `.accentColor` |
| Submit disabled | `Color.secondary.opacity(0.2)` |

## Ghostty Codebase Alignment

- **Value types**: `Workspace`, `WorkspaceTemplate`, and `TagDefinition` are all structs (value types), consistent with Ghostty's preference for value semantics.
- **Observable pattern**: Uses `@ObservedObject` for `WorktreeManager`, consistent with the app's use of `ObservableObject` for shared state.
- **Git via Process**: Uses `/usr/bin/git` directly via `Process` (same as `GitShell` and `GitService`), consistent with avoiding libgit2 dependencies.
- **Persistence**: Recent repos via `UserDefaults`; workspace state via `WorktreeManager` which persists to `~/.ghostset/state.json`.
- **Window integration**: The sheet is presented modally from `WorkspaceWindow` / `WorkspaceSidebar`, fitting into the `WorkspaceWindowController` -> `WorkspaceWindow` -> `NewWorkspaceSheet` hierarchy.
- **No AppKit mixing**: Pure SwiftUI implementation — no NSViewRepresentable, except the use of `NSOpenPanel` in `browseForRepo()` which is the standard macOS pattern.

## Known Issues

1. **"None" agent button is a no-op**: The "None" menu item in the agent picker has an empty action closure `{ }`. It does not set `selectedAgent` to `nil` or any sentinel value. Users who want no agent cannot deselect the current agent.

2. **Blocking `waitUntilExit()` in Swift concurrency Task**: Both `cloneRepo()` and `createEmptyRepo()` call `p.waitUntilExit()` inside a `Task { }` block. This blocks a cooperative thread from Swift's concurrency pool, which can cause thread starvation under load. Should use `Process.terminationHandler` or wrap in a `withCheckedContinuation`.

3. **No input sanitization on clone URL beyond protocol check**: `isValidGitURL` only checks URL prefix. Malformed URLs or paths with spaces could cause unexpected behavior in the git clone process.

4. **No validation of `emptyRepoName`**: The name field accepts any non-empty string, including strings with spaces, special characters, or path traversal sequences (e.g., `../`). The `sanitize()` function is only applied to `workspaceName`, not to `emptyRepoName`.

5. **`colorScheme` environment is captured but unused**: `@Environment(\.colorScheme) private var colorScheme` is declared but never referenced in the view body.

6. **`FlowLayout` defined but unused**: The `FlowLayout` struct at the bottom of the file is not used by any view in this file. It may be dead code or used elsewhere via implicit import.

7. **Git stderr is captured but never read**: In `cloneRepo()`, stderr is piped (`p.standardError = Pipe()`) but the pipe's data is never read. If the buffer fills, the process could deadlock. In `createEmptyRepo()`, stderr is not captured at all.

8. **No branch name validation**: The new branch name field in the branch picker accepts any non-whitespace input, including characters invalid for git branch names (e.g., `~`, `^`, `:`, `?`, `*`, `[`, `\`).

9. **Race condition on `isAddingRepo`**: Both `cloneRepo()` and `createEmptyRepo()` use `isAddingRepo` as a guard, but it is set on the main actor before entering the `Task` and reset inside the `Task`. If errors occur, the flag is correctly reset, but there is no `defer` block ensuring cleanup.

10. **Recent repos can reference deleted directories**: `loadRecentRepos()` returns paths from UserDefaults without checking if they still exist on disk. The repo picker will show stale entries.

## Future Enhancements

1. **Fix "None" agent option**: Add a proper nil/none state to clear the selected agent.
2. **Async git operations**: Replace `waitUntilExit()` with `Process.terminationHandler` wrapped in `withCheckedContinuation` to avoid blocking cooperative threads.
3. **Branch name validation**: Validate against git's branch naming rules (no `..`, no ASCII control characters, no `~^:?*[\`, no trailing `.lock`, etc.).
4. **Empty repo name sanitization**: Apply the same `sanitize()` logic used for workspace names.
5. **Stale recent repo cleanup**: Filter `loadRecentRepos()` results through `FileManager.fileExists()` before display.
6. **Clone progress streaming**: Read stderr from the clone process and display progress percentage in the UI.
7. **Template management in-sheet**: Allow creating/editing templates directly from the sheet rather than requiring a separate settings view.
8. **Keyboard navigation**: Add focus management and tab order between fields.
9. **Repo bookmarks**: Use security-scoped bookmarks instead of raw paths for sandboxed app compatibility.
10. **Language tag auto-detection**: Call `TagDefinition.detectLanguageTags(repoPath:)` when a repo is selected and merge results into `selectedTags`.

## Changelog

- **2026-03-20**: Initial spec — complete documentation of all UI sections, state properties, interactions, git operations, popovers, validation logic, design tokens, and known issues.
