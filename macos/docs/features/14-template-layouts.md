# Template Layouts — Full Workspace Snapshots

## Overview

Templates evolve from simple workspace presets (agent + branch + tags) into full workspace layout snapshots. A template captures the complete tab and split configuration: how many tabs, what each tab runs, how splits are arranged, what commands auto-run in each split, and all visual customizations (pin, color, icon). When applied, a template recreates the exact layout in a new workspace — tabs open, splits arrange, and commands execute automatically.

## Problem Statement

Currently, templates only store: name, repo, branch, agent, tags, task description. When creating a workspace from a template, you get a single terminal tab. Users who have complex setups (e.g., 4 tabs with splits running `make run`, `yarn dev`, `celery worker`, `claude`) must manually recreate this layout every time they create a new workspace for a similar project.

## Design Goals

1. **One-click layout recreation** — apply a template, get the exact same tab/split/command layout
2. **Visual preview** — see the layout before applying it
3. **Editable** — modify templates without needing a running workspace
4. **Portable** — clean JSON format for sharing between machines/teams
5. **Backward compatible** — old templates (no tabs field) still work

## Data Model

### TemplateTab
```swift
struct TemplateTab: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String           // Tab display name
    var agent: AgentType?       // Agent to launch (claude, codex, etc.)
    var command: String?        // Command to run (overrides agent)
    var autoRun: Bool           // true = press Enter; false = pre-fill only
    var isPinned: Bool          // Pin state
    var colorName: String?      // Tab color
    var iconOverride: String?   // Custom SF Symbol
    var splits: [TemplateSplit] // Split pane definitions (empty = single pane)
}
```

### TemplateSplit
```swift
struct TemplateSplit: Codable, Identifiable, Hashable {
    let id: UUID
    var command: String?        // Command to run in this split
    var autoRun: Bool           // Auto-press Enter
    var subdirectory: String?   // Relative path from worktree root
    var direction: SplitDirection // .horizontal or .vertical
}
```

### WorkspaceTemplate (updated)
```swift
struct WorkspaceTemplate {
    // ... existing fields ...
    var tabs: [TemplateTab]     // NEW: full tab layout (empty = legacy single-tab)
}
```

## JSON Format

### Example: Full-Stack Development Template
```json
{
    "name": "Full-Stack Dev",
    "baseBranch": "main",
    "category": "Custom",
    "tags": ["feature"],
    "setupCommand": "npm install",
    "tabs": [
        {
            "title": "Backend",
            "command": "make run",
            "autoRun": true,
            "isPinned": true,
            "colorName": "green",
            "iconOverride": "server.rack",
            "splits": []
        },
        {
            "title": "Frontend",
            "command": "yarn dev",
            "autoRun": true,
            "colorName": "blue",
            "iconOverride": "globe",
            "splits": [
                {
                    "command": "yarn test --watch",
                    "autoRun": true,
                    "subdirectory": "frontend",
                    "direction": "horizontal"
                }
            ]
        },
        {
            "title": "Workers",
            "splits": [
                {
                    "command": "make run-worker",
                    "autoRun": true,
                    "subdirectory": "api",
                    "direction": "vertical"
                },
                {
                    "command": "make run-user-actions",
                    "autoRun": true,
                    "subdirectory": "api",
                    "direction": "vertical"
                }
            ]
        },
        {
            "title": "Claude",
            "agent": "claude",
            "autoRun": true,
            "isPinned": true,
            "colorName": "orange"
        }
    ]
}
```

### Example: Simple Agent Template (backward compatible)
```json
{
    "name": "Claude Feature",
    "baseBranch": "main",
    "agent": "claude",
    "tags": ["feature"],
    "tabs": []
}
```

## Capture Flow (Save as Template)

### Trigger
Right-click workspace → "Save as Template"

### What Gets Captured
1. Iterate `tabGroup.tabs`
2. For each tab:
   - Title, agent, isPinned, colorName, iconOverride
   - Iterate `tab.viewModel.surfaceTree` surfaces
   - For each surface: capture `title` (as command if it looks like one), `pwd` (as subdirectory relative to worktree root)
   - Record split directions from the tree structure
3. Workspace metadata: tags, branch, env vars, setup command

### Command Detection Heuristic
A surface title is treated as a command if:
- Not empty
- Does NOT contain `@` (rules out `user@host:path` prompts)
- Does NOT start with `/` or `~` (rules out absolute paths)

### Subdirectory Detection
Surface `pwd` is compared to workspace `worktreePath`:
- If pwd starts with worktreePath, the remainder is the subdirectory
- e.g., worktree `/home/user/.ghostset/worktrees/app/feature`, pwd `/home/user/.ghostset/worktrees/app/feature/api` → subdirectory `api`

## Apply Flow (Create from Template)

### When template has tabs
1. Create workspace (git worktree)
2. For each `TemplateTab`:
   a. Create a new tab via `vmCache.createTab()`
   b. Set isPinned, colorName, iconOverride
   c. If tab has an agent: set `config.initialInput = agent.launchCommand + "\n"`
   d. If tab has a command (no agent): set `config.initialInput = command + (autoRun ? "\n" : "")`
   e. For each `TemplateSplit` in the tab:
      - Create a new split in the specified direction
      - Set working directory to `worktreePath/subdirectory`
      - Set `config.initialInput = split.command + (autoRun ? "\n" : "")`
3. Run setupCommand if specified

### When template has no tabs (legacy)
Fall back to current behavior: single tab with agent from template.

## Template Manager UI

### Layout Preview
Each template in the manager shows a miniature visual preview:

```
┌─────────────────────────────────┐
│ Template: Full-Stack Dev        │
│                                 │
│ ┌──────┐ ┌──────┐ ┌────┐ ┌──┐  │
│ │Server│ │ Web  │ │Work│ │AI│  │
│ │ make │ │ yarn ├──┤ers ├──┤  │  │
│ │ run  │ │ dev  │ │    │ │  │  │
│ │📌    │ │  │tst│ │w│ua│ │📌│  │
│ └──────┘ └──────┘ └────┘ └──┘  │
│                                 │
│ 4 tabs · 2 pinned · 6 commands  │
└─────────────────────────────────┘
```

The preview shows:
- Tab count and arrangement
- Split layout per tab (nested rectangles)
- Command names truncated inside each pane
- Pin icons on pinned tabs
- Color indicators

### Template Editor (expanded)
Clicking a template in the manager opens an editor with:

#### Tab List (left column)
- Draggable list of tabs
- Each shows: icon, title, agent badge, pin toggle, color dot
- "+" to add tab, "×" to remove
- Drag to reorder

#### Selected Tab Detail (right column)
- Title field
- Agent picker (or "None")
- Command field with "Auto-run" toggle
- Pin toggle
- Color picker
- Icon picker

#### Split Layout Editor (below tab detail)
- Visual split preview for the selected tab
- "Add Split" button (horizontal/vertical)
- Each split shows:
  - Command field
  - Subdirectory field
  - Auto-run toggle
  - Direction toggle (H/V)
  - Remove button

### Summary Bar (bottom)
- `4 tabs · 2 splits · 5 commands · 2 pinned`
- Export / Import buttons

## Implementation Plan

### Phase 1: Data Model (done)
- [x] `TemplateTab` struct with command, autoRun, splits
- [x] `TemplateSplit` struct with command, subdirectory, direction
- [x] `WorkspaceTemplate.tabs` field
- [x] Backward-compatible decoding
- [x] `snapshot()` factory method

### Phase 2: Capture
- [ ] Fix `snapshot()` to properly walk split tree structure (not just iterate surfaces)
- [ ] Record split directions from `SplitTree.Node.split` cases
- [ ] Test with complex layouts (nested splits)

### Phase 3: Apply
- [ ] Update `NewWorkspaceSheet` to apply template tabs on creation
- [ ] Create splits programmatically via `SplitTree.inserting()`
- [ ] Set per-split working directories and commands
- [ ] Respect autoRun flag (append "\n" or not)

### Phase 4: Preview
- [ ] Create `TemplateLayoutPreview` SwiftUI view
- [ ] Render tab pills + split rectangles from template data
- [ ] Show commands inside panes
- [ ] Add to template row in `TemplateManagerView`

### Phase 5: Editor
- [ ] Create `TemplateLayoutEditor` SwiftUI view
- [ ] Tab list with add/remove/reorder
- [ ] Per-tab command, agent, pin, color, icon editors
- [ ] Split editor with add/remove/direction
- [ ] Live preview updates

### Phase 6: Import/Export
- [ ] Validate imported JSON against schema
- [ ] Show preview before importing
- [ ] Export single template (not just "Export All")
- [ ] Copy template JSON to clipboard

## Known Constraints

1. **Split tree structure** — `SplitTree` is recursive (binary tree of horizontal/vertical splits). Capturing and recreating this exactly requires walking the tree, not just iterating leaves.
2. **Command detection is heuristic** — surface titles aren't always the running command. `make run` shows as "make run" but some processes set custom titles.
3. **Subdirectories may not exist** — if a template references `api/` but the new repo doesn't have that directory, the split falls back to the worktree root.
4. **Split creation timing** — splits must be created sequentially (each needs the previous surface to exist as an anchor point). This requires async coordination.
5. **No scrollback restoration** — templates recreate the layout and re-run commands, but don't restore terminal history.

## Future Enhancements

- **Template marketplace** — share templates via GitHub gists or a central registry
- **Project detection** — auto-suggest templates based on repo contents (package.json → Node template, Cargo.toml → Rust template)
- **Template variables** — `{{port}}`, `{{env}}` placeholders that prompt on creation
- **Hooks** — pre/post creation hooks for template-specific setup
- **Template versioning** — track changes to templates over time
- **Screenshot capture** — save a screenshot of the layout as the preview image

## Changelog

- 2026-03-20: Initial spec created
- 2026-03-20: Added TemplateTab and TemplateSplit to WorkspaceTemplate model
- 2026-03-20: Added snapshot() factory method for capturing current workspace layout
- 2026-03-20: Defined JSON format with examples
- 2026-03-20: Planned 6-phase implementation
