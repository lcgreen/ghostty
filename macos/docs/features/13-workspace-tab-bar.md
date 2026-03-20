# Workspace Tab Bar

## Overview

A custom per-workspace tab bar providing independent tab groups for each workspace. Each workspace maintains its own tabs (shells, agents), and switching workspaces swaps the tab set. The tab bar visually matches Ghostty's native titlebar tabs — full-width equal-split capsule tabs with left-aligned close buttons, centered titles, and right-aligned shortcut labels. Tab titles sync from the terminal surface's pty title. Tabs support drag-to-reorder, pinning, custom colors/icons, and context menus.

## Architecture

### Key Files

| File | Role |
|------|------|
| `WorkspaceTabBar.swift` | SwiftUI tab bar view with drag, pin, color, context menu |
| `WorkspaceViewModelCache.swift` | `WorkspaceTabGroup` + `WorkspaceTabEntry` data models |
| `WorkspaceWindow.swift` | Hosts tab bar, wires callbacks, manages title sync timer |
| `WorkspaceWindowController.swift` | Cmd+1-9/Cmd+W/Cmd+T keyboard intercepts |

### Data Models

#### WorkspaceTabEntry
| Property | Type | Purpose |
|----------|------|---------|
| `id` | `UUID` | Unique tab identifier |
| `title` | `String` | Display title (synced from surface, starts empty) |
| `viewModel` | `WorkspaceTerminalViewModel` | Owns the terminal's `SplitTree<SurfaceView>` |
| `agent` | `AgentType?` | Non-nil for agent tabs (title not auto-overridden) |
| `sessionID` | `String?` | Agent session ID for resume |
| `isPinned` | `Bool` | Pinned tabs can't be closed, shown as compact icon |
| `colorName` | `String?` | Custom tab color (tinted background + bottom indicator) |
| `iconOverride` | `String?` | Custom SF Symbol icon |

#### WorkspaceTabGroup
| Method | Purpose |
|--------|---------|
| `addTab(_:activate:)` | Add tab, optionally make active |
| `closeTab(id:)` | Remove tab, activate nearest neighbor |
| `selectTab(id:)` | Switch active tab by UUID |
| `selectTab(at:)` | Switch active tab by index (keyboard) |
| `togglePin(id:)` | Pin/unpin, moves pinned tabs to front |
| `setTabColor(id:color:)` | Set custom color |
| `setTabIcon(id:icon:)` | Set custom icon |
| `moveTab(id:toIndex:)` | Reorder tab |
| `updateActiveTabTitle(_:)` | Update title (skips agent tabs) |
| `syncTabTitlesFromSurfaces()` | Sync all titles from terminal surfaces |

## Tab Bar Layout

```
┌─────────────────────────────────────────────────────────────────┐
│ [pin] │ ✕  title...  ⌘1 │ ✕  ✦ claude  ⌘2 │ ✕  title  ⌘3 │ + │
│ 40px  │     equal-width     │    equal-width    │  equal-width  │   │
└─────────────────────────────────────────────────────────────────┘
```

- **≤6 tabs**: fill width equally (`maxWidth: .infinity`)
- **>6 tabs**: scroll horizontally (`maxWidth: 220`)
- **Pinned tabs**: compact 40px, show only agent icon or pin icon
- **Close (✕)**: left-aligned, always visible (prevents layout reflow)
- **Title**: centered, truncated with `.tail`, empty shows "…"
- **Shortcut (⌘N)**: right-aligned for tabs 1-9
- **Active tab**: capsule background `Color.primary.opacity(0.1)`
- **Tab bar hidden**: when only 1 tab (Cmd+T to add)

## Keyboard Shortcuts

| Shortcut | Action | Implementation |
|----------|--------|----------------|
| `⌘T` | New tab | Controller posts `.ghostsetNewWorkspaceTab` |
| `⌘1-⌘9` | Switch tab | `NSEvent` local monitor → `selectTab(at:)` |
| `⌘W` | Close tab | `NSEvent` monitor → `closeTab(id:)` (skips pinned, falls through to window close with 1 tab) |
| `⌘D` | Split (Ghostty) | Handled by `WorkspaceSplitDelegate` |

## Title Sync

- 300ms timer calls `syncTabTitlesFromSurfaces()` on the active `TerminalView`
- Reads raw `surface.title` from each tab's surface — same title Ghostty uses
- **500ms stability threshold**: title only applies after being stable for 500ms (prevents flicker when terminal rapidly changes titles)
- Agent tabs never have title overridden
- New tabs start with empty title ("…" placeholder), filled by pty
- `pwdDidChange` and `focusedSurfaceDidChange` also update titles as fallback

## Context Menu (right-click)

| Action | Behavior |
|--------|----------|
| Close Tab | Closes tab (disabled if pinned or last tab) |
| Close Other Tabs | Closes all except this (skips pinned) |
| Close Tabs to the Right | Closes tabs after this (skips pinned) |
| Pin/Unpin Tab | Toggles pin state |
| Move Left/Right | Reorders via context menu |
| Tab Color | Submenu: None + 8 colors (blue, green, orange, red, purple, teal, pink, indigo) |
| Tab Icon | Submenu: Default + 8 icons (Terminal, Web, Server, Build, Test, Docs, Debug, Script) |
| Detach to Window | Removes tab, creates standalone Ghostty `TerminalController` with the surface tree |
| Move to Workspace | Submenu listing all workspaces — closes tab here, creates fresh tab in target workspace |
| Duplicate Tab | Creates new tab |
| New Shell Tab | Creates new tab |

## Tab Pinning

- Pinned tabs show compact (40px) with just the agent icon or pin icon
- No title, no close button, no shortcut label
- Can't be closed with ✕ or Cmd+W
- Auto-sorted to the left when pinned
- "Close Others" and "Close Right" skip pinned tabs

## Tab Colors

- Active colored tab: tinted capsule background (`color.opacity(0.12)`) + 2px colored bottom indicator
- Color picker in context menu with 8 options
- Custom icon inherits tab color if set

## Drag-to-Reorder

- `onDrag` provides tab UUID via `NSItemProvider` as plain text
- `onDrop` with `TabDropDelegate` swaps tabs on `dropEntered`
- Dragged tab dims to 40% opacity
- Animated with 200ms ease-in-out
- **Known issue**: dropping on terminal pastes UUID text (acceptable trade-off)

## Session Persistence

- Tabs auto-save to `~/.ghostset/sessions/{workspaceID}.json`
- Save triggers: new tab, close tab, workspace switch, every 30 seconds, app quit
- Saves: title, agent, sessionID, splitLayout (with working directory from `surface.pwd`)
- Restores: recreates tabs with correct working directories and agent resume commands
- Split delegate rebinds `viewModel` on tab switch (ensures splits work on active tab)

## Known Issues

1. **Title sync polling** — 300ms timer, not event-driven. Combine subscriber was unreliable.
2. **Drag drops UUID on terminal** — `NSItemProvider` with `.utf8PlainText` can paste into terminal if dropped outside tab bar.
3. **Two `selectTab` methods** — `selectTab(id:)` for UI, `selectTab(at:)` for keyboard. Both needed.

## Future Enhancements

- **Drag-to-tear-off** — physical drag outside tab bar creates Ghostty window (currently context menu only)
- **Tab preview on hover** — thumbnail of terminal content
- **Event-driven title sync** — replace timer with Combine when surface lifecycle allows
- **Tab overflow indicator** — show count of hidden tabs when scrolling
- **Tab groups/nesting** — group related tabs within a workspace

## Changelog

- 2026-03-20: Initial spec
- 2026-03-20: Switched from native macOS tabs to custom tab bar
- 2026-03-20: Full-width equal-split layout matching Ghostty native style
- 2026-03-20: Left-aligned close buttons prevent layout reflow
- 2026-03-20: Cmd+1-9 keyboard shortcuts, Cmd+W tab close
- 2026-03-20: Tab titles sync from raw surface title, start blank
- 2026-03-20: 500ms title stability threshold prevents flicker
- 2026-03-20: Tab pinning with compact display
- 2026-03-20: Tab colors and custom icons
- 2026-03-20: Context menu with close/pin/color/icon/detach/move
- 2026-03-20: Drag-to-reorder with custom UTType (reverted to plain text)
- 2026-03-20: Detach to Window creates standalone Ghostty TerminalController
- 2026-03-20: Move to Workspace creates fresh tab in target
- 2026-03-20: Auto-save sessions on tab changes + every 30 seconds
- 2026-03-20: Working directories persist from surface.pwd
- 2026-03-20: Split delegate rebinds on tab switch (fixes Cmd+D after tab switch)
