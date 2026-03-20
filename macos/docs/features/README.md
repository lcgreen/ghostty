# Ghostset Feature Specifications

Living documentation for every feature in the Ghostset workspace orchestration layer built on top of Ghostty.

## Feature Index

| # | Feature | Spec | Primary Source |
|---|---------|------|----------------|
| 01 | [Workspace Sidebar](01-workspace-sidebar.md) | Search, filter, sort, drag reorder, context menus | `WorkspaceSidebar.swift` |
| 02 | [Workspace Cards](02-workspace-cards.md) | Agent icon, name, branch, tags, status, stats | `WorkspaceRow.swift` |
| 03 | [Tag System](03-tag-system.md) | Colored tags, auto-tagging, language detection | `TagDefinition.swift` |
| 04 | [New Workspace Sheet](04-new-workspace-sheet.md) | Unified creation with templates, agents, branches | `NewWorkspaceSheet.swift` |
| 05 | [Git Status Panel](05-git-status-panel.md) | VS Code-style source control panel | `GitStatusPanel.swift` |
| 06 | [Workspace Diff View](06-workspace-diff-view.md) | Cross-workspace comparison and merge | `WorkspaceDiffView.swift` |
| 07 | [Command Palette](07-command-palette.md) | Cmd+K fuzzy search for all actions | `WorkspaceCommandPalette.swift` |
| 08 | [Template System](08-template-system.md) | Save, manage, import/export templates | `WorkspaceTemplate.swift`, `TemplateManagerView.swift` |
| 09 | [Workspace Settings](09-workspace-settings.md) | Env profiles, setup commands, shell config | `WorkspaceSettingsPopover.swift` |
| 10 | [Notifications](10-notifications.md) | macOS notifications, unread badges | `WorkspaceNotifier.swift` |
| 11 | [Workspace Persistence](11-workspace-persistence.md) | State, sessions, window state, restoration | `WorkspacePersistence.swift` |
| 12 | [Workspace Window & Controller](12-native-tab-integration.md) | NSWindowController, split delegate, session persistence | `WorkspaceWindowController.swift`, `WorkspaceWindow.swift` |
| 13 | [Workspace Tab Bar](13-workspace-tab-bar.md) | Per-workspace tabs with drag, pin, color, split, persistence | `WorkspaceTabBar.swift`, `WorkspaceViewModelCache.swift` |
| 14 | [Template Layouts](14-template-layouts.md) | Full workspace snapshots: tabs, splits, commands, auto-run | `WorkspaceTemplate.swift`, `TemplateManagerView.swift` |

## Architecture Overview

```
Ghostty (Zig core) → GhosttyKit.xcframework → macOS App (Swift/AppKit/SwiftUI)
                                                    ↓
                                              Ghostset Layer
                                                    ↓
                    ┌─────────────────────────────────────────────────┐
                    │  WorkspaceWindowController (NSWindowController) │
                    │  ├── WorkspaceWindow (SwiftUI)                  │
                    │  │   ├── WorkspaceSidebar                      │
                    │  │   │   ├── WorkspaceRow (per workspace)      │
                    │  │   │   └── GitStatusPanel (toggle)           │
                    │  │   └── Detail (TerminalView)                 │
                    │  │       └── AgentPresetsBar                   │
                    │  └── WorkspaceCommandPalette (overlay)         │
                    └─────────────────────────────────────────────────┘
                              ↕                    ↕
                    WorktreeManager          WorkspacePersistence
                    ├── Workspace[]          ├── state.json
                    ├── TagDefinition[]      ├── sessions/
                    ├── Template[]           ├── templates.json
                    └── WorkspaceNotifier    └── window-state.json
```

## Data Storage

| File | Contents |
|------|----------|
| `~/.ghostset/state.json` | Workspaces, tags, clean shutdown flag |
| `~/.ghostset/sessions/{uuid}.json` | Per-workspace terminal tab state |
| `~/.ghostset/window-state.json` | Window tab restoration |
| `~/.ghostset/templates.json` | Workspace templates |
| `~/.ghostset/worktrees/{repo}/{name}/` | Git worktree directories |
| `{repo}/.ghostset/config.json` | Per-repo workspace config |

## Conventions

- **Immutability**: Workspace is a value type (struct). Updates create new copies via `WorktreeManager` methods.
- **Background I/O**: All persistence saves dispatch to `DispatchQueue.global(qos: .utility)`.
- **Git operations**: Run via `Process` on background threads, never block main thread.
- **Naming**: Feature files prefixed with `Workspace` except standalone types (`TagDefinition`, `AgentType`).

## Updating These Specs

When modifying a feature:
1. Update the corresponding spec file
2. Add an entry to the Changelog section at the bottom
3. Update Known Issues if fixed
4. Update Future Enhancements if implemented
