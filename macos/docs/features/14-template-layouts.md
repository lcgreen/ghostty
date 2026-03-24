# Template Layouts — Full Workspace Snapshots

## Overview

Templates capture complete workspace layouts: tabs, splits, commands, agents, and visual settings. When applied, a template recreates the exact layout — tabs open, splits arrange, and commands auto-execute. On app restart, workspaces with a linked template re-apply it fresh so commands auto-run every launch.

## Status: Implemented

All phases are complete:

- [x] **Data Model** — `TemplateTab`, `TemplateSplit`, `TemplatePane` (recursive), `WorkspaceTemplate.tabs`
- [x] **Capture** — `WorkspaceTemplate.snapshot()` walks split tree, captures commands and layout
- [x] **Apply** — `WorkspaceViewModelCache.applyTemplate()` creates tabs with splits and auto-run commands
- [x] **Preview** — `TemplateLayoutPreview` with tab headers + split structure blocks, `TemplateLayoutSummary`
- [x] **Editor** — `TemplateLayoutEditor` with tab list, detail panel, split editor, lifecycle commands
- [x] **Lifecycle** — `onCreateCommand` / `onDestroyCommand` run via `/bin/sh` in worktree
- [x] **Startup Restore** — workspaces with `templateID` re-apply template fresh on launch
- [x] **Apply to Existing** — right-click workspace → Apply Template
- [x] **Session Persistence** — `SplitCommand` in session state for non-templated workspaces

## Data Model

### TemplateTab
```swift
struct TemplateTab: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String           // Tab display name
    var agent: AgentType?       // Agent to launch (claude, codex, etc.)
    var command: String?        // Command to run (if no agent)
    var autoRun: Bool           // true = press Enter; false = pre-fill only
    var isPinned: Bool
    var colorName: String?
    var iconOverride: String?   // Custom SF Symbol
    var splits: [TemplateSplit] // Flat split definitions
    var layout: TemplatePane?   // Recursive layout (takes precedence)
}
```

### TemplateSplit
```swift
struct TemplateSplit: Codable, Identifiable, Hashable {
    let id: UUID
    var command: String?
    var autoRun: Bool
    var subdirectory: String?
    var direction: SplitDirection // .horizontal or .vertical
}
```

### TemplatePane (recursive)
```swift
indirect enum TemplatePane: Codable, Identifiable, Hashable {
    case terminal(TemplatePaneLeaf)
    case split(TemplatePaneSplit)
}
```

### WorkspaceTemplate (key fields)
```swift
struct WorkspaceTemplate: Codable, Identifiable, Hashable {
    var tabs: [TemplateTab]         // Full tab layout
    var onCreateCommand: String?    // Shell script run after creation
    var onDestroyCommand: String?   // Shell script run before deletion
    // ... plus name, agent, baseBranch, tags, category, etc.
}
```

### Workspace (template link)
```swift
struct Workspace {
    var templateID: UUID?           // Links to WorkspaceTemplate.id
    var onCreateCommand: String?    // Copied from template on apply
    var onDestroyCommand: String?   // Copied from template on apply
}
```

### CRITICAL: Equatable/Hashable
All template types use **compiler-synthesized** `Equatable`/`Hashable`. Never add id-only implementations — SwiftUI uses these for change detection, and id-only comparison makes all mutations invisible.

## Flows

### Apply Template (to new or existing workspace)
1. User selects template via New Workspace sheet or right-click → Apply Template
2. `templateID` set on workspace, lifecycle commands copied
3. `onCreateCommand` runs in worktree via `WorktreeManager.runLifecycleCommand`
4. `WorkspaceViewModelCache.applyTemplate()` creates tabs:
   - For each `TemplateTab`: create `WorkspaceTerminalViewModel`
   - If recursive `layout` exists: `buildTree()` / `buildNode()` recursively
   - Otherwise: main pane + flat `splits` via `SplitTree.inserting()`
   - Commands set via `config.initialInput = command + (autoRun ? "\n" : "")`
5. Session saved immediately (1s delay)

### Startup Restore
1. `WorkspaceViewModelCache.tabGroup(for:)` checks `workspace.templateID`
2. If template found: re-applies fresh via `applyTemplate()` (skips session restore)
3. Commands auto-run because template has `autoRun: true`
4. If no template: falls back to session restore from `WorkspacePersistence`

### Save as Template
1. Right-click workspace → "Save as Template"
2. `WorkspaceTemplate.snapshot(workspace:tabGroup:)` walks live `SplitTree`
3. Captures: tab titles, agents, split directions, working directories, command heuristics
4. Saves via `WorktreeManager.saveTemplate()`

### Delete Workspace
1. `onDestroyCommand` runs in worktree
2. Status set to `.deleting` (orange indicator in sidebar)
3. `git worktree remove` runs async
4. Workspace removed from list on completion

## Template Layout Editor

### Architecture
- `@State private var template: WorkspaceTemplate` — internal state, not `@Binding`
- `init(original:onSave:)` — initializes state from original, calls `onSave` on Done
- Tab selection by `UUID` (not integer index)
- All bindings use `$template.tabs[idx]` directly

### UI Structure
```
┌─────────────────────────────────────────────┐
│ Template Name                                │
├──────────┬──────────────────────────────────┤
│ Tab List │  Selected Tab Detail              │
│ + ∧ ∨ −  │  Title, Agent, Command, Pin,     │
│          │  Color, Icon, Splits              │
├──────────┴──────────────────────────────────┤
│ ▸ LIFECYCLE COMMANDS ●                       │
│   On Create [NSTextView]  On Destroy [...]   │
├─────────────────────────────────────────────┤
│ [Preview: tab cards with split blocks]       │
│ 4 tabs · 4 splits · 9 cmds · 1 pinned       │
├─────────────────────────────────────────────┤
│ Copy JSON                            [Done]  │
└─────────────────────────────────────────────┘
```

### Lifecycle Commands
- Multi-line `NSTextView` via `MultilineTextView` (NSViewRepresentable)
- Supports paste (Cmd+V), undo, multi-line editing
- Collapsible section with green dot indicator when commands are set

## JSON Format

### Example
```json
{
    "name": "Full-Stack Dev",
    "baseBranch": "main",
    "category": "Custom",
    "tags": ["feature"],
    "onCreateCommand": "cp ~/Source/app/.env ./app\nnpm install",
    "onDestroyCommand": "docker compose down",
    "tabs": [
        {
            "title": "Claude",
            "agent": "claude",
            "autoRun": true,
            "isPinned": true
        },
        {
            "title": "Backend",
            "command": "make run",
            "autoRun": true,
            "colorName": "green",
            "splits": [
                {
                    "command": "make run-worker",
                    "autoRun": true,
                    "subdirectory": "api",
                    "direction": "vertical"
                }
            ]
        },
        {
            "title": "Frontend",
            "command": "yarn dev",
            "autoRun": true,
            "colorName": "blue"
        }
    ]
}
```

## Known Constraints

1. **Split tree structure** — recursive binary tree; captured/recreated by walking the tree
2. **Command detection is heuristic** — surface titles aren't always the running command
3. **Subdirectories may not exist** — falls back to worktree root
4. **Template changes don't propagate** — editing a template doesn't update existing workspaces
5. **Sheets not resizable** — macOS `.sheet` limitation

## Changelog

- 2026-03-20: Initial spec, data model, JSON format
- 2026-03-24: Full implementation complete — editor, preview, lifecycle commands, startup restore, Apply Template, deleting status
