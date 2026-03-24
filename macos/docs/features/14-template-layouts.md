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

## JSON Reference

### Field Reference

#### WorkspaceTemplate (top-level object)

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `id` | string (UUID v4) | No | auto-generated | Stable identifier for the template |
| `name` | string | Yes | — | Display name shown in the template picker |
| `agent` | AgentType object | No | null | Default agent for new workspaces created from this template |
| `baseBranch` | string | No | null | Git branch to use as the worktree base (e.g. `"main"`) |
| `tags` | array of string | No | `[]` | Freeform labels for filtering |
| `category` | string | No | `"Custom"` | Category shown in the template manager (e.g. `"Work"`, `"Personal"`) |
| `onCreateCommand` | string | No | null | Shell script run after the workspace is created or the template is applied |
| `onDestroyCommand` | string | No | null | Shell script run before the worktree is deleted |
| `tabs` | array of TemplateTab | Yes | — | Ordered list of tabs to open |
| `variables` | array of TemplateVariable | No | `[]` | Named variables prompted at apply time |

#### TemplateTab

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `id` | string (UUID v4) | No | auto-generated | Stable tab identifier |
| `title` | string | Yes | — | Tab display name |
| `agent` | AgentType object | No | null | Agent to launch in this tab |
| `command` | string | No | null | Command to run (used when no agent is set) |
| `autoRun` | bool | No | `false` | `true` = press Enter after pre-filling; `false` = pre-fill only |
| `isPinned` | bool | No | `false` | Pin the tab so it can't be closed accidentally |
| `colorName` | string | No | null | Tab accent color (e.g. `"red"`, `"green"`, `"blue"`, `"orange"`, `"purple"`) |
| `iconOverride` | string | No | null | SF Symbol name for a custom tab icon |
| `splits` | array of TemplateSplit | No | `[]` | Flat list of additional panes (applied if `layout` is absent) |
| `layout` | TemplatePane object | No | null | Recursive split tree; takes precedence over `splits` when present |

#### TemplateSplit

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `id` | string (UUID v4) | No | auto-generated | Stable split identifier |
| `command` | string | No | null | Command to run in this pane |
| `autoRun` | bool | No | `false` | Press Enter after pre-filling |
| `subdirectory` | string | No | null | Path relative to the worktree root (falls back to root if missing) |
| `direction` | string | Yes | — | `"horizontal"` (side-by-side) or `"vertical"` (stacked) |

#### TemplatePane (recursive, two variants)

**Terminal leaf** — a single pane with an optional command:
```json
{
  "terminal": {
    "_0": {
      "id": "...",
      "command": "npm test",
      "autoRun": true,
      "subdirectory": "packages/core"
    }
  }
}
```

**Split node** — two child panes and a direction:
```json
{
  "split": {
    "_0": {
      "id": "...",
      "first": { "<TemplatePane>" },
      "second": { "<TemplatePane>" },
      "direction": "horizontal"
    }
  }
}
```

#### AgentType encoding

Swift encodes `AgentType` as a keyed object, not a bare string:

| Agent | JSON encoding |
|-------|--------------|
| Claude | `{"claude": {}}` |
| Codex | `{"codex": {}}` |
| Gemini | `{"gemini": {}}` |
| Cursor | `{"cursor": {}}` |
| Custom | `{"custom": "my-agent"}` |

---

### Minimal Example

The simplest valid template — one tab, no splits, no lifecycle commands:

```json
[
  {
    "name": "Scratch",
    "tabs": [
      {
        "title": "Terminal",
        "autoRun": false
      }
    ]
  }
]
```

---

### Full-Featured Example

```json
[
  {
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "name": "Full-Stack Dev — {{projectName}}",
    "baseBranch": "main",
    "category": "Work",
    "tags": ["feature", "fullstack"],
    "onCreateCommand": "cp ~/Source/app/.env ./app\nnpm install --prefix app",
    "onDestroyCommand": "docker compose -f app/docker-compose.yml down",
    "variables": [
      {
        "name": "projectName",
        "prompt": "Project display name",
        "defaultValue": "MyApp"
      }
    ],
    "tabs": [
      {
        "id": "11111111-1111-1111-1111-111111111111",
        "title": "Claude",
        "agent": {"claude": {}},
        "autoRun": true,
        "isPinned": true,
        "colorName": "purple",
        "iconOverride": "brain"
      },
      {
        "id": "22222222-2222-2222-2222-222222222222",
        "title": "Backend",
        "command": "make run",
        "autoRun": true,
        "colorName": "green",
        "layout": {
          "split": {
            "_0": {
              "id": "33333333-3333-3333-3333-333333333333",
              "direction": "horizontal",
              "first": {
                "terminal": {
                  "_0": {
                    "id": "44444444-4444-4444-4444-444444444444",
                    "command": "make run",
                    "autoRun": true,
                    "subdirectory": "api"
                  }
                }
              },
              "second": {
                "terminal": {
                  "_0": {
                    "id": "55555555-5555-5555-5555-555555555555",
                    "command": "make run-worker",
                    "autoRun": true,
                    "subdirectory": "api"
                  }
                }
              }
            }
          }
        }
      },
      {
        "id": "66666666-6666-6666-6666-666666666666",
        "title": "Frontend — {{projectName}}",
        "command": "yarn dev",
        "autoRun": true,
        "colorName": "blue",
        "splits": [
          {
            "id": "77777777-7777-7777-7777-777777777777",
            "command": "yarn test --watch",
            "autoRun": false,
            "subdirectory": "web",
            "direction": "vertical"
          }
        ]
      }
    ]
  }
]
```

---

### Notes

**UUID generation** — Any UUID v4 is valid. Generate one in the terminal with:
```bash
uuidgen | tr '[:upper:]' '[:lower:]'
```
Omitting `id` fields is also fine; they are auto-generated on import.

**Date format** — Dates (if used in variable defaults or commands) should follow ISO 8601, e.g. `2026-03-24T12:00:00Z`.

**Agent encoding** — `AgentType` is a Swift enum encoded as a keyed object: `{"claude": {}}`, not `"claude"`. Passing a bare string will fail to decode.

**TemplatePane encoding** — The indirect enum encodes with a type wrapper: `{"terminal": {"_0": {...}}}` for leaf nodes and `{"split": {"_0": {...}}}` for split nodes. The `_0` key is the Swift synthesized associated-value label.

**Variable substitution** — `{{name}}` placeholders in any string field are replaced with the value provided at apply time. Use `\{{` to emit a literal `{{`. Substitution is single-pass (variables in replacement values are not expanded again).

**`validated()` cleanup** — When a template is applied or imported, `validated()` removes agent-title-only tab commands (commands that match the agent name used as a display title), and clears degenerate flat splits that duplicate the main pane. This keeps snapshots captured from live workspaces clean.

**File location** — Templates are stored in `~/.ghostset/templates.json` as a JSON **array** of `WorkspaceTemplate` objects (not a single object). The file is created automatically when you save your first template via the UI.

## Known Constraints

1. **Split tree structure** — recursive binary tree; captured/recreated by walking the tree
2. **Subdirectories may not exist** — falls back to worktree root
3. **Command detection heuristic** — when capturing a live workspace, the snapshot filters out tab titles that begin with `@`, `/`, or `~`, or contain non-ASCII symbols, treating them as agent-generated display strings rather than runnable commands
4. **Single-pass variable substitution** — `{{variable}}` placeholders are expanded once; if a replacement value itself contains `{{...}}`, those inner placeholders are not expanded

## Changelog

- 2026-03-20: Initial spec, data model, JSON format
- 2026-03-24: Full implementation complete — editor, preview, lifecycle commands, startup restore, Apply Template, deleting status
- 2026-03-24: Import deduplication, auto-propagate template edits, resizable editor window (NSWindow)
- 2026-03-24: Branch validation, template variables (`{{name}}` substitution + prompt UI), JSON validation (`validated()` cleans snapshots), optional baseBranch, template indicator in workspace sidebar rows
