# Template System

## Overview

The template system provides reusable workspace configurations that can be saved, edited, duplicated, imported, and exported. A `WorkspaceTemplate` captures agent type, base branch, tags, tab/split layouts with auto-run commands, lifecycle hooks (onCreate/onDestroy), and category. The `TemplateManagerView` offers a full CRUD interface organized by category, `TemplateLayoutEditor` provides a full tab/split editor, and `TemplatePersistence` handles JSON serialization to `~/.ghostset/templates.json`.

## Architecture

### Key Files

| File | Role |
|------|------|
| `Sources/Features/Workspace/WorkspaceTemplate.swift` | `WorkspaceTemplate`, `TemplateTab`, `TemplateSplit`, `TemplatePane`, `TemplatePersistence`, `TemplateCategory` |
| `Sources/Features/Workspace/TemplateManagerView.swift` | SwiftUI sheet for template CRUD management |
| `Sources/Features/Workspace/TemplateLayoutEditor.swift` | Full tab/split/command editor with live preview |
| `Sources/Features/Workspace/TemplateLayoutPreview.swift` | Miniature visual preview (tab headers + split structure blocks) |

### Data Models

**WorkspaceTemplate** (struct, Codable, Identifiable, Hashable)
- `id: UUID` — unique identifier, generated on creation
- `name: String` — template display name
- `repoPath: String?` — optional default repository path
- `baseBranch: String` — branch to create worktrees from (default: `"main"`)
- `agent: AgentType?` — optional agent to auto-launch
- `tags: [String]` — tag labels to apply to created workspaces
- `taskDescription: String?` — optional task description
- `environmentVariables: [String: String]` — custom environment variables
- `setupCommand: String?` — optional shell command (legacy)
- `onCreateCommand: String?` — multi-line script to run after workspace creation
- `onDestroyCommand: String?` — multi-line script to run before workspace deletion
- `category: TemplateCategory` — organizational category
- `tabs: [TemplateTab]` — full tab layout with splits and commands
- `createdAt: Date` — creation timestamp

**TemplateTab** (struct, Codable, Identifiable, Hashable)
- `id: UUID`, `title: String`, `agent: AgentType?`, `command: String?`, `autoRun: Bool`
- `isPinned: Bool`, `colorName: String?`, `iconOverride: String?`
- `splits: [TemplateSplit]` — flat split definitions
- `layout: TemplatePane?` — recursive split layout (takes precedence over flat splits)

**TemplateSplit** (struct, Codable, Identifiable, Hashable)
- `id: UUID`, `command: String?`, `autoRun: Bool`, `subdirectory: String?`, `direction: SplitDirection`

**TemplatePane** (indirect enum, Codable, Identifiable, Hashable)
- `.terminal(TemplatePaneLeaf)` — single pane with command
- `.split(TemplatePaneSplit)` — recursive split with direction, first, second

**CRITICAL: Equatable/Hashable** — All template types use **compiler-synthesized** conformances (comparing all fields). Do NOT add id-only `==` or `hash(into:)` — this breaks SwiftUI reactivity since state changes won't be detected.

### Feature Connections

- **WorktreeManager** — manages template list via `manager.templates`, `manager.saveTemplate()`, `manager.removeTemplate()`, `manager.replaceAllTemplates()`
- **Workspace** — `templateID: UUID?` links workspace to its template for startup restore
- **WorkspaceSidebar** — "Apply Template" context menu sets `templateID`, copies lifecycle commands, applies layout
- **WorkspaceViewModelCache** — on startup, if workspace has `templateID`, re-applies template fresh (skips session restore)
- **Session Persistence** — `SplitCommand` stores commands for session-based restore (fallback when no template)

## Template Lifecycle

### 1. Create/Edit
- Templates are created in `TemplateManagerView` or via "Save as Template" from workspace context menu
- `TemplateLayoutEditor` provides full editing: tabs, splits, commands, visual settings, lifecycle commands
- Editor uses `@State` internally (not `@Binding`) for reliable SwiftUI reactivity

### 2. Apply to Workspace
When applying a template (new workspace or context menu → Apply Template):
1. `templateID` is set on the workspace
2. `onCreateCommand` and `onDestroyCommand` are copied to the workspace
3. `onCreateCommand` runs via `/bin/sh` in the worktree directory (`WorktreeManager.runLifecycleCommand`)
4. Tab layout is applied via `WorkspaceViewModelCache.applyTemplate()` — creates tabs with splits and auto-run commands
5. Session is saved immediately (1s delay) for persistence

### 3. Startup Restore
When the app launches and a workspace has a `templateID`:
- The template is re-applied fresh (same as clicking "Apply Template")
- This ensures commands auto-run on every restart
- Session restore is skipped for templated workspaces

### 4. Destroy
When a workspace is deleted:
- `onDestroyCommand` runs in the worktree before `git worktree remove`
- Workspace shows "Deleting..." status (orange) during async deletion

## Template Layout Editor

### Architecture
- Presented as a `.sheet` from `TemplateManagerView`
- Uses `@State private var template: WorkspaceTemplate` (not `@Binding`) for reliable reactivity
- Calls `onSave(template)` callback on Done
- Tab selection tracked by `selectedTabID: UUID?` (not integer index)

### Layout
- **Left panel** (180px): Tab list with selection, up/down reorder buttons, add/remove
- **Right panel**: Selected tab detail (title, agent, command, pin, color, icon, splits)
- **Lifecycle Commands**: Collapsible section with `NSTextView`-backed multi-line editors (supports paste)
- **Preview**: `TemplateLayoutPreview` showing tab structure with `TemplateLayoutSummary`
- **Footer**: Copy JSON, Done button

### Window Dimensions
| View | Min Width | Min Height |
|------|-----------|------------|
| TemplateManagerView | 420 | 400 |
| TemplateLayoutEditor | 560 | 480 |

Note: macOS `.sheet` modals are not resizable.

## Template Preview

`TemplateLayoutPreview` shows a miniature visual representation:
- Each tab renders as a card with a colored header (tab name) and split structure
- Splits shown as colored block rectangles (not text) for clarity at small sizes
- All tabs have equal height via `.frame(maxHeight: .infinity)`
- Tab names auto-scale with `.minimumScaleFactor(0.6)`
- `TemplateLayoutSummary` shows: "N tabs · N splits · N cmds · N pinned"

## Data Storage

- Templates: `~/.ghostset/templates.json`
- Workspace state (including `templateID`): `~/.ghostset/state.json`
- Sessions: `~/.ghostset/sessions/{workspaceID}.json`

## Known Issues

1. **Import does not deduplicate**: Importing templates with the same name creates duplicates
2. **No validation on branch name**: The base branch field accepts any string
3. **Sheets not resizable**: macOS `.sheet` modals are fixed-size
4. **Template changes don't auto-propagate**: Editing a template doesn't update workspaces already using it (must re-apply)

## Future Enhancements

- Template marketplace / sharing via GitHub gists
- Project detection — auto-suggest templates based on repo contents
- Template variables (`{{port}}`, `{{env}}`) that prompt on creation
- Template versioning / history
- Present editor as a resizable window instead of sheet

## Changelog

- 2026-03-20: Initial spec
- 2026-03-24: Full implementation — layout editor, preview, lifecycle commands, startup restore, Apply Template action, Open Project, deleting status
