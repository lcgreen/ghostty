# Workspace Window & Controller

## Overview

The workspace window architecture connects the Ghostset workspace system to Ghostty's terminal core. `WorkspaceWindowController` is an NSWindowController that hosts the SwiftUI `WorkspaceWindow`, intercepts Ghostty core notifications (new tab, split, command palette), manages keyboard shortcuts (Cmd+1-9, Cmd+W, Cmd+T), and handles session persistence/restoration. `WorkspaceWindow` is the root SwiftUI view providing a `NavigationSplitView` (sidebar + detail), command palette overlay, and a view model cache for instant workspace switching. `WorkspaceSplitDelegate` bridges all of Ghostty's split pane notifications into the workspace terminal.

**Note:** The tab bar UI itself is documented in [13-workspace-tab-bar.md](13-workspace-tab-bar.md). This doc covers the window/controller layer beneath it.

## Architecture

### Key Files

| File | Role |
|------|------|
| `WorkspaceWindowController.swift` | NSWindowController, keyboard intercepts, session save/restore |
| `WorkspaceWindow.swift` | Root SwiftUI view, NavigationSplitView, command palette overlay |
| `WorkspaceViewModelCache.swift` | Tab group management, per-workspace VM caching |

### Feature Connections

- **WorkspaceTabBar** — rendered inside `WorkspaceDetailContent`
- **WorkspaceSidebar** — sidebar column of NavigationSplitView
- **WorkspaceCommandPalette** — overlay triggered by Cmd+K
- **TerminalView** — renders active tab's surface tree
- **AgentPresetsBar** — status bar agent launch buttons

## Current Implementation

### WorkspaceWindowController

- Creates NSWindow with `tabbingMode = .disallowed` (custom tab bar instead)
- Registers `NSEvent` local key monitor for Cmd+1-9 (tab switch) and Cmd+W (tab close)
- Monitor reference stored in `keyEventMonitor`, removed in `deinit`
- Intercepts `ghosttyNewTab` and `ghosttyCommandPaletteDidToggle` notifications
- Routes Cmd+T to internal tab creation via `.ghostsetNewWorkspaceTab` notification
- `surfaceConfiguration(for:)` sets working directory and env vars from workspace

### WorkspaceWindow (SwiftUI)

- `NavigationSplitView` with sidebar (200-350px) + detail
- `vmCache` (`WorkspaceViewModelCache`) persists tab groups across workspace switches
- `splitDelegate` (`WorkspaceSplitDelegate`) handles all Ghostty split operations
- Auto-saves sessions on: tab create, tab close, workspace switch, every 30 seconds, app quit
- Command palette overlay with Cmd+K shortcut (hidden Button)

### WorkspaceSplitDelegate

Bridges 6 Ghostty core notifications:
- `ghosttyNewTab` → posts `.ghostsetNewWorkspaceTab`
- `ghosttyNewSplit` → creates new SurfaceView, inserts into split tree
- `didEqualizeSplits` → equalizes all split ratios
- `ghosttyFocusSplit` → moves focus to adjacent split
- `didToggleSplitZoom` → toggles split pane zoom
- `didResizeSplit` → resizes splits by amount/direction

Rebinds `viewModel` on tab switch to ensure splits work on the active tab.

## Known Issues

1. `bindActiveViewModel` uses `DispatchQueue.main.async` which can race with window hierarchy
2. `onNewSplit` accesses `AppDelegate` directly via `NSApplication.shared.delegate` cast

## Changelog

- 2026-03-20: Initial spec
- 2026-03-20: Switched from native macOS tabs to custom tab bar
- 2026-03-20: Added Cmd+W tab close, Cmd+1-9 switching with stored monitor
- 2026-03-20: Added auto-save on tab changes and every 30 seconds
- 2026-03-20: Fixed split delegate rebinding on tab switch
- 2026-03-20: Renamed from "Native Tab Integration" to "Workspace Window & Controller"
