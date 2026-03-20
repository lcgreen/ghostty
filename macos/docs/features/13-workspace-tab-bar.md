# Workspace Tab Bar

## Overview

A custom per-workspace tab bar that provides independent tab groups for each workspace. Each workspace maintains its own set of tabs (shells, agents), and switching workspaces in the sidebar switches the entire tab set. The tab bar visually matches Ghostty's native titlebar tabs — full-width equal-split capsule tabs with left-aligned close buttons, centered titles, and right-aligned ⌘N shortcut labels. Tab titles sync automatically from the terminal surface's title (set by the pty via escape codes).

## Architecture

### Key Files

| File | Role |
|------|------|
| `WorkspaceTabBar.swift` | SwiftUI view rendering the tab bar UI |
| `WorkspaceViewModelCache.swift` | `WorkspaceTabGroup` model managing per-workspace tab state, `WorkspaceTabEntry` per-tab data |
| `WorkspaceWindow.swift` | Hosts the tab bar in `WorkspaceDetailContent`, creates tabs via `addNewTab()` |
| `WorkspaceWindowController.swift` | Intercepts Cmd+T for new tabs, Cmd+1-9 for tab switching, Ghostty core new-tab notifications |

### Data Models

#### `WorkspaceTabEntry`
```swift
struct WorkspaceTabEntry: Identifiable {
    let id: UUID
    var title: String          // Synced from surface.title
    let viewModel: WorkspaceTerminalViewModel  // Owns the SplitTree<SurfaceView>
    var agent: AgentType?      // Non-nil for agent tabs (title not overridden)
    var sessionID: String?     // Agent session ID for resume
}
```

#### `WorkspaceTabGroup`
```swift
class WorkspaceTabGroup: ObservableObject {
    @Published var tabs: [WorkspaceTabEntry]
    @Published var activeTabID: UUID?
}
```

### Feature Connections

- **WorkspaceViewModelCache** — caches one `WorkspaceTabGroup` per workspace UUID. Switching workspaces swaps which tab group is displayed.
- **WorkspaceSplitDelegate** — subscribes to active surface's `$title` publisher for tab name updates.
- **WorkspaceWindowController** — intercepts keyboard events (Cmd+1-9, Cmd+T) before Ghostty's core.
- **TerminalView** — each tab's `WorkspaceTerminalViewModel.surfaceTree` is rendered by a `TerminalView`.
- **AgentPresetsBar** — launches agents into new tabs via `onLaunchAgent`.

## Current Implementation

### Tab Bar Layout

```
┌──────────────────────────────────────────────────────────────┐
│ ✕  title-from-pty    ⌘1 │     title-from-pty    ⌘2 │  +   │
└──────────────────────────────────────────────────────────────┘
```

- Tabs fill available width equally (`frame(maxWidth: .infinity)`)
- Active tab has capsule background (`Color.primary.opacity(0.1)`)
- Close button (✕) is **left-aligned** and always visible (prevents layout reflow)
- Title is **centered** with `.lineLimit(1)` and `.truncationMode(.tail)`
- Shortcut label (⌘N) is **right-aligned**
- Agent tabs show agent icon with color before the title
- "+" button is fixed-width at the end

### Tab Bar Visibility

The tab bar only renders when `tabGroup.tabs.count > 1`. With a single tab, the terminal fills the full detail area.

### Title Syncing

Tab titles are synced from the terminal surface via a 300ms timer:

```swift
.onReceive(Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()) { _ in
    tabGroup.syncTabTitlesFromSurfaces()
}
```

`syncTabTitlesFromSurfaces()` iterates all non-agent tabs and reads `surface.title` directly. Agent tabs keep their agent name and are never overridden.

New tabs start with an empty title (`""`) and get populated when the terminal sets its title via pty escape codes — matching Ghostty's native behavior.

### Keyboard Shortcuts

| Shortcut | Action | Handler |
|----------|--------|---------|
| `⌘T` | New tab in current workspace | `WorkspaceWindowController.newTab(_:)` → posts `.ghostsetNewWorkspaceTab` |
| `⌘1` - `⌘9` | Switch to tab N | `NSEvent.addLocalMonitorForEvents` in controller, calls `group.selectTab(at:)` |
| `⌘W` | Close current tab (if >1) or window | Ghostty core handles this |

The Cmd+1-9 handler:
- Only activates when the workspace has 2+ tabs
- Checks `event.window == self.window` to scope to the correct window
- Returns `nil` to consume the event (prevents Ghostty's core from handling it)
- Only fires for Cmd (no Shift, no Option modifiers)

### Tab Creation Flow

1. User presses Cmd+T or clicks "+" in tab bar
2. `WorkspaceWindowController.newTab(_:)` posts `.ghostsetNewWorkspaceTab`
3. `WorkspaceWindow` receives notification, calls `addNewTab(agent:)`
4. `addNewTab` calls `vmCache.createTab(for: workspace, ...)` with empty title
5. `WorkspaceViewModelCache.createTab()` creates a `WorkspaceTerminalViewModel` with a new `SurfaceView`
6. If agent is specified, `config.initialInput = agent.launchCommand + "\n"` launches the agent
7. Tab entry is added to the workspace's `WorkspaceTabGroup`
8. SwiftUI re-renders the tab bar

### Tab Close Flow

1. User clicks ✕ on a tab
2. `onCloseTab` callback fires with tab UUID
3. `WorkspaceTabGroup.closeTab(id:)` removes the entry
4. If the closed tab was active, activates the nearest remaining tab
5. `bindActiveViewModel()` updates the split delegate and controller references

### Agent Tab Behavior

- Agent tabs show the agent icon (colored) before the title
- Agent tab titles use `agent.displayName` and are **not overridden** by surface title sync
- When created with a task description, the task is sent as initial input after the agent command

### Native Tab Suppression

Native macOS tabs are disabled on the workspace window:
```swift
window.tabbingMode = .disallowed
```

The `onGhosttyNewTab` notification from Ghostty's core is intercepted and routed to the custom tab system instead of creating native tabs.

## UI Specifications

### Dimensions

| Element | Value |
|---------|-------|
| Tab bar height | ~34px (3px vertical padding + 28px content) |
| Tab horizontal padding | 4px outer, 6-8px inner |
| Close button size | 16×16px |
| Close icon size | 8pt, weight: bold |
| Title font | 12pt system |
| Shortcut font | 9pt monospaced |
| Agent icon | 9pt |
| "+" button | 32×28px |
| Tab spacing | 2px between tabs |

### Colors

| Element | Color |
|---------|-------|
| Active tab background | `Color.primary.opacity(0.1)` capsule |
| Inactive tab background | Clear |
| Active title | `.primary` |
| Inactive title | `.secondary` |
| Close button | `.tertiary` |
| Shortcut (active) | `.tertiary` |
| Shortcut (inactive) | `.quaternary` |
| Agent icon | `AgentColors.color(for: agent)` |
| "+" button | `.secondary` |

## Design Consistency

### Matches Ghostty Native Tabs
- Full-width equal-split layout ✓
- Capsule/pill shape for active tab ✓
- Close button left-aligned, always visible ✓
- ⌘N shortcut labels ✓
- Title centered ✓
- Tabs start blank, title fills from pty ✓

### Differences from Ghostty Native Tabs
- Custom SwiftUI implementation (not NSWindow tab groups)
- Per-workspace tab groups (native tabs are per-window)
- No drag-to-reorder (native tabs support this)
- No drag-to-tear-off (native tabs create new windows)
- No tab overview mode

## Ghostty Codebase Alignment

### Types Used
- `Ghostty.SurfaceView` — terminal surface, `$title` publisher
- `Ghostty.SurfaceConfiguration` — `initialInput` for agent launch, `workingDirectory`
- `Ghostty.Notification.ghosttyNewTab` — intercepted to route to custom tabs
- `TerminalView` — renders the active tab's surface tree
- `SplitTree<Ghostty.SurfaceView>` — owned by each tab's `WorkspaceTerminalViewModel`
- `AgentType` — determines agent icon and whether title sync is suppressed

### Integration Points
- `WorkspaceWindowController` registers `NSEvent` local monitor for Cmd+1-9
- Ghostty core's `ghosttyNewTab` notification is intercepted (surface window check)
- `TerminalViewDelegate.focusedSurfaceDidChange` updates tab titles
- `TerminalViewDelegate.pwdDidChange` also updates tab titles as fallback

## Known Issues

1. **Title sync uses polling (300ms timer)** — not event-driven. Uses 500ms stability threshold to prevent flicker. Combine `$title` subscriber was unreliable due to surface lifecycle timing.
2. **`selectTab(id:)` vs `selectTab(at:)`** — two selection methods with different semantics (UUID vs index). Both are needed (UI uses id, keyboard uses index).

## Implemented Features

### Keyboard Shortcuts
- **⌘T** — new tab in current workspace
- **⌘1-⌘9** — switch to tab N (intercepted via `NSEvent.addLocalMonitorForEvents`, monitor stored and cleaned up in deinit)
- **⌘W** — close active tab when multiple tabs exist; falls through to window close with single tab

### Tab Context Menu (right-click)
- Close Tab
- Close Other Tabs
- Close Tabs to the Right
- Duplicate Tab
- New Shell Tab

### Tab Bar Visibility
Tab bar is always visible (even with single tab) so the "+" button is always accessible.

### Title Stability
Titles only update after 500ms of stability — prevents flickering when the terminal rapidly changes titles (e.g., Claude Code alternating between path and app name).

### Drag-to-Reorder
Tabs support drag-and-drop reordering within the tab bar. Dragging provides the tab's UUID as `NSItemProvider` data; dropping moves the tab to the new position in the group.

## Future Enhancements

- **Drag-to-tear-off** — dragging a tab out creates a new workspace window
- **Tab pinning** — pin tabs that can't be closed and stay at the left
- **Tab preview on hover** — show a thumbnail of the terminal content
- **Event-driven title sync** — replace timer with proper Combine subscription when surface lifecycle is more predictable
- **Tab overflow** — scroll or dropdown when too many tabs to fit
- **Tab color/icon customization** — let users set per-tab colors or icons
- **Move to workspace** — context menu option to move a tab to a different workspace

## Changelog

- 2026-03-20: Initial spec created
- 2026-03-20: Switched from native macOS tabs to custom tab bar (native tabs don't support per-workspace tab groups)
- 2026-03-20: Added full-width equal-split layout matching Ghostty's native tab style
- 2026-03-20: Added left-aligned close buttons to prevent layout reflow
- 2026-03-20: Added Cmd+1-9 keyboard shortcuts via NSEvent local monitor
- 2026-03-20: Tab titles sync from raw surface title (no shortening), start blank like Ghostty
- 2026-03-20: Fixed — Cmd+W closes tab (not window) when multiple tabs exist
- 2026-03-20: Fixed — Tab bar always visible (single tab shows "+" button)
- 2026-03-20: Fixed — Event monitor stored and removed in deinit
- 2026-03-20: Fixed — Title flicker prevented with 500ms stability threshold
- 2026-03-20: Added tab context menu (Close, Close Others, Close Right, Duplicate)
- 2026-03-20: Added drag-to-reorder tabs
