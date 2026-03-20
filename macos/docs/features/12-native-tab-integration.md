# Native Tab Integration

## Overview

The native tab integration connects the workspace system to macOS native window tabbing and the Ghostty terminal core. `WorkspaceWindowController` is an NSWindowController that hosts a SwiftUI `WorkspaceWindow` view inside an NSHostingView, manages native macOS titlebar tabs, intercepts Ghostty core notifications for new tabs and command palette, and handles session persistence/restoration. `WorkspaceWindow` is the root SwiftUI view providing a `NavigationSplitView` with sidebar and detail areas, a command palette overlay, a view model cache for instant workspace switching, and a split delegate that bridges Ghostty's split pane system into the workspace terminal.

## Architecture

### Key Files

| File | Role |
|------|------|
| `Sources/Features/Workspace/WorkspaceWindowController.swift` | NSWindowController subclass, native tab management, Ghostty integration, session persistence |
| `Sources/Features/Workspace/WorkspaceWindow.swift` | Root SwiftUI view, NavigationSplitView, command palette overlay, session saving |

### Data Models

No new data models are defined in these files. They consume:
- `Workspace`, `WorkspaceStatus` from WorkspaceModel.swift
- `WindowState`, `WindowTabState` from WorkspacePersistence.swift
- `WorkspaceSessionState`, `TabSessionState`, `SplitLayout` from session types
- `AgentType` from AgentType.swift

### Feature Connections

- **Ghostty.App** -- provides `app` (core instance), `workspaceManager` (WorktreeManager), environment object
- **WorkspaceSidebar** -- sidebar view receiving `manager` and `selectedWorkspaceID` binding
- **WorkspaceCommandPalette** -- overlay palette receiving `manager`, `selectedWorkspaceID`, `isPresented`
- **WorkspaceViewModelCache** -- caches terminal view models per workspace for instant switching
- **WorkspaceTabGroup** -- groups custom tabs within a workspace
- **WorkspaceTerminalViewModel** -- manages surface tree for a terminal tab
- **WorkspaceSplitDelegate** -- bridges Ghostty split notifications to SwiftUI
- **TerminalView** -- renders the Ghostty terminal surface
- **AgentPresetsBar** -- bottom bar with agent launch buttons
- **WorkspacePersistence** -- saves/loads window and session state
- **Ghostty.SurfaceView** -- individual terminal surface
- **Ghostty.SurfaceConfiguration** -- terminal surface configuration

## Current Implementation

### WorkspaceWindowController

#### Class Properties

| Property | Type | Purpose |
|----------|------|---------|
| `activeControllers` | `static Set<WorkspaceWindowController>` (private) | Strong references keeping controllers alive while windows are open |
| `all` | `static [WorkspaceWindowController]` (computed) | Array of all active controllers |
| `hasWindows` | `static Bool` (computed) | Whether any workspace windows exist |

#### Instance Properties

| Property | Type | Purpose |
|----------|------|---------|
| `ghostty` | `Ghostty.App` (private) | Reference to Ghostty application core |
| `selectedWorkspaceID` | `UUID?` | Workspace this tab was opened with (nil = blank terminal) |
| `initialSplitLayout` | `SplitLayout?` (private, readonly) | Persisted split layout to restore |
| `initialAgent` | `AgentType?` (private, readonly) | Agent to auto-launch in this tab |
| `agentSessionID` | `String?` | Agent session ID for resume (e.g., Claude session ID) |
| `titleOverride` | `String?` (private, readonly) | Custom title set by user |
| `terminalViewModel` | `weak WorkspaceTerminalViewModel?` | Reference to active terminal view model |
| `activeTabGroup` | `weak WorkspaceTabGroup?` | Reference to active tab group |

#### Initializer

```swift
init(_ ghostty: Ghostty.App, workspaceID: UUID?, splitLayout: SplitLayout?,
     title: String?, agent: AgentType?, agentSessionID: String?)
```

Creates an NSWindow with:
- Content rect: 1200 x 800
- Style mask: titled, closable, miniaturizable, resizable, fullSizeContentView
- Title: "Ghostty" (hidden titlebar, transparent titlebar)
- Toolbar style: `.unifiedCompact`
- Min size: 600 x 400
- Tabbing mode: `.automatic` (native macOS titlebar tabs)
- `isRestorable = false` (custom persistence instead)
- Content view: `NSHostingView(rootView: WorkspaceWindow(...))`

Registers notification observers:
- `Ghostty.Notification.ghosttyNewTab` -- `onGhosttyNewTab(_:)`
- `.ghosttyCommandPaletteDidToggle` -- `onGhosttyCommandPalette(_:)`

Inserts self into `activeControllers` for retention.

#### Notification Handlers

| Handler | Notification | Purpose |
|---------|-------------|---------|
| `onGhosttyNewTab(_:)` | `ghosttyNewTab` | Checks if the surface belongs to this window, then calls `newTab(nil)` |
| `onGhosttyCommandPalette(_:)` | `ghosttyCommandPaletteDidToggle` | Checks if the surface belongs to this window, then calls `toggleCommandPalette(nil)` |

Both handlers verify the notification's `SurfaceView` belongs to this window before acting.

#### Tab Title Management

| Method | Purpose |
|--------|---------|
| `changeTabTitle(_:)` | `@objc @IBAction` -- Shows NSAlert sheet with text field for custom title. Updates `titleOverride`, `window.title`, and active custom tab title. Empty input restores default "Ghostty" title. |

#### Command Palette

| Method | Purpose |
|--------|---------|
| `toggleCommandPalette(_:)` | `@IBAction` -- Toggles `terminalViewModel.commandPaletteIsShowing` |

#### Menu Validation

| Method | Purpose |
|--------|---------|
| `validateMenuItem(_:)` | Validates `toggleCommandPalette` (requires terminalViewModel), `changeTabTitle` (always valid), `newTab` (always valid) |

#### Native Tab Management

| Method | Purpose |
|--------|---------|
| `newTab(_:)` | `@IBAction` -- Cmd+T handler, calls `createNativeTab(agent: nil)` |
| `newTabWithAgent(_:)` | Creates a native tab with a specific agent |
| `createNativeTab(agent:)` | Creates a new `WorkspaceWindowController` with the same `selectedWorkspaceID`, calls `showWindow`, adds to parent's tab group via `parentWindow.addTabbedWindow(newWindow, ordered: .above)` |

#### Window Delegate

| Method | Purpose |
|--------|---------|
| `windowWillClose(_:)` | Sets `window.contentView = nil` to deallocate SurfaceViews before Zig core tick (prevents dangling pointers). Removes self from `activeControllers`. |

#### Static Session Management

| Method | Purpose |
|--------|---------|
| `saveWindowTabState()` | Iterates all controllers, saves per-workspace `WorkspaceSessionState` via `WorkspacePersistence.saveSession()`, and saves `WindowState` via `saveWindowState()` for backward compat. |
| `controllers(for:)` | Returns all controllers matching a given workspace ID |
| `restoreWindowTabs(_:)` | Loads `WindowState`, groups tabs by workspace, creates controllers, adds tabbed windows. Returns `true` if restoration occurred. First window gets focus via `makeKeyAndOrderFront`. |

#### Terminal Surface Factory (extension)

| Method | Purpose |
|--------|---------|
| `surfaceConfiguration(for:)` | Static method creating `Ghostty.SurfaceConfiguration` with `workingDirectory` set to workspace's `worktreePath` and `environmentVariables` from `AgentLauncher.environmentVariables(for:)` |

### WorkspaceWindow (SwiftUI View)

#### Properties

| Property | Type | Purpose |
|----------|------|---------|
| `initialWorkspaceID` | `UUID?` | Workspace ID to select on appear |
| `initialSplitLayout` | `SplitLayout?` | Split layout to restore |
| `initialAgent` | `AgentType?` | Agent to auto-launch |
| `agentSessionID` | `String?` | Agent session ID for resume |

#### State Properties

| Property | Type | Purpose |
|----------|------|---------|
| `ghostty` | `@EnvironmentObject Ghostty.App` | Ghostty application core |
| `selectedWorkspaceID` | `@State UUID?` | Currently selected workspace |
| `columnVisibility` | `@State NavigationSplitViewVisibility` | Sidebar visibility (default: `.doubleColumn`) |
| `isReady` | `@State Bool` | Guards detail view rendering until after initial setup |
| `showingCommandPalette` | `@State Bool` | Command palette overlay visibility |
| `showingGitPanel` | `@State Bool` | Git panel visibility (declared but not used in body) |
| `vmCache` | `@StateObject WorkspaceViewModelCache` | Cached terminal view models per workspace |
| `splitDelegate` | `@StateObject WorkspaceSplitDelegate` | Bridges split pane notifications |

#### Body Structure

```
Group {
    if ghostty.app != nil {
        NavigationSplitView(columnVisibility:) {
            WorkspaceSidebar(...)          // sidebar column
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        } detail: {
            detailView                     // terminal + status bar
        }
        .navigationSplitViewStyle(.balanced)
    } else {
        WelcomeView()                      // shown when Ghostty.App not ready
    }
}
.onReceive(.ghostsetSaveSession)           // save all sessions
.overlay {
    if showingCommandPalette {
        Color.black.opacity(0.3)           // dimming backdrop
        WorkspaceCommandPalette(...)       // palette with .padding(.top, 60)
    }
}
.background {
    Button("") { ... }                     // hidden Cmd+K shortcut
        .keyboardShortcut("k", modifiers: .command)
        .hidden()
}
```

#### Lifecycle Handlers

| Handler | Purpose |
|---------|---------|
| `.onAppear` | Sets `selectedWorkspaceID` from `initialWorkspaceID` or first workspace. Defers `isReady = true` and `bindActiveViewModel()` to next main queue tick. |
| `.onChange(of: selectedWorkspaceID)` | Calls `syncToController()` and `bindActiveViewModel()` |
| `.onReceive(.ghostsetNewWorkspaceTab)` | Extracts agent from notification userInfo, calls `launchAgent()` |
| `.onReceive(.ghostsetSaveSession)` | Calls `saveAllSessions()` |

#### Detail View (`WorkspaceDetailContent`)

Private struct observing `@ObservedObject WorkspaceTabGroup`. Contains:
- `TerminalView` rendering the active tab's surface tree (keyed by `tabGroup.activeTabID`)
- Divider
- Status bar with:
  - `AgentPresetsBar` for launching agents
  - Workspace info: agent icon (`.system(size: 9)`), name (`.system(size: 11, weight: .medium)`, `.secondary`), branch (`.system(size: 10, design: .monospaced)`, `.tertiary`)
  - Status dot: 5x5 circle colored by `WorkspaceStatus`
  - Height: 22, background: `.ultraThinMaterial`

#### Methods

| Method | Purpose |
|--------|---------|
| `selectedWorkspace` | Computed -- finds workspace in manager by `selectedWorkspaceID` |
| `activeTabGroup` | Computed -- gets or creates tab group from `vmCache` for current workspace |
| `addNewTab(agent:)` | Creates a new tab in the view model cache |
| `bindActiveViewModel()` | Sets `splitDelegate.viewModel` and `workspaceID`, updates `WorkspaceWindowController.terminalViewModel` and `activeTabGroup` on next main queue tick |
| `syncToController(_:)` | Updates `WorkspaceWindowController.selectedWorkspaceID` to match SwiftUI state |
| `launchAgent(_:)` | Calls `controller.newTabWithAgent()` to create a native tab with the agent |
| `saveAllSessions()` | Iterates `vmCache.allGroups`, saves `WorkspaceSessionState` for each workspace via `workspaceManager.saveSession()` |

### WorkspaceSplitDelegate

`NSObject` subclass, `ObservableObject`, implements `TerminalViewDelegate`.

#### Properties

| Property | Type | Purpose |
|----------|------|---------|
| `viewModel` | `weak WorkspaceTerminalViewModel?` | Active terminal view model |
| `workspaceID` | `UUID?` | Current workspace ID |

#### Notification Observers (registered in init)

| Notification | Handler | Purpose |
|-------------|---------|---------|
| `ghosttyNewTab` | `onNewTab(_:)` | Posts `.ghostsetNewWorkspaceTab` when surface belongs to current view model |
| `ghosttyNewSplit` | `onNewSplit(_:)` | Creates new `Ghostty.SurfaceView` and inserts into split tree at the correct direction |
| `didEqualizeSplits` | `onEqualize(_:)` | Equalizes all split ratios in the surface tree |
| `ghosttyFocusSplit` | `onFocusSplit(_:)` | Moves focus to adjacent split in specified direction |
| `didToggleSplitZoom` | `onZoom(_:)` | Toggles zoom on a split pane (zooms single pane or restores all) |
| `didResizeSplit` | `onResize(_:)` | Resizes a split by the specified amount and direction |

#### TerminalViewDelegate Methods

| Method | Purpose |
|--------|---------|
| `focusedSurfaceDidChange(to:)` | Updates window title from surface title (unless `titleOverride` is set) |
| `pwdDidChange(to:)` | Updates window title from directory name, records `cd` command in `commandHistory` |
| `cellSizeDidChange(to:)` | No-op |
| `performAction(_:on:)` | No-op |
| `performSplitAction(_:)` | Handles `.resize` and `.drop` split operations on the surface tree |

#### Split Operations Detail

**onNewSplit**: Extracts `direction` from userInfo (`ghostty_action_split_direction_e`), maps to `SplitTree.NewDirection` (RIGHT/LEFT/DOWN/UP), creates new `SurfaceView` via `Ghostty.SurfaceView(app, baseConfig: cfg)`, inserts into tree, moves focus.

**onResize**: Extracts direction and amount from userInfo, maps to `SplitTree.Spatial.Direction`, calculates bounds from `viewBounds()`, calls `surfaceTree.resizing(node:by:in:with:)`.

**performSplitAction(.drop)**: Handles drag-and-drop of splits -- if source exists in tree, removes then reinserts at destination; if new, just inserts.

### Custom Notifications

| Name | Defined In | Purpose |
|------|-----------|---------|
| `.ghostsetSaveSession` | WorkspaceWindowController.swift | `"com.ghostset.saveSession"` -- triggers session save |
| `.ghostsetNewWorkspaceTab` | Defined elsewhere, received here | Triggers native tab creation |
| `.ghosttyCommandPaletteDidToggle` | Defined elsewhere, received here | Toggles command palette |

## Design Consistency

| Element | Font | Color | Spacing |
|---------|------|-------|---------|
| Workspace name (status bar) | `.system(size: 11, weight: .medium)` | `.secondary` | -- |
| Branch name (status bar) | `.system(size: 10, design: .monospaced)` | `.tertiary` | -- |
| Agent icon (status bar) | `.system(size: 9)` | `.accentColor` | -- |
| Status dot | -- | Status-specific color | 5x5, trailing 2 |
| Status bar | -- | `.ultraThinMaterial` bg | height 22, horizontal 8 |
| Sidebar column | -- | -- | min 200, ideal 250, max 350 |
| Window | -- | -- | 1200x800 default, 600x400 min |
| Command palette overlay | -- | `Color.black.opacity(0.3)` | top 60 |

## Ghostty Codebase Alignment

### Types Used
- `Ghostty.App` (app property, workspaceManager, environmentObject)
- `Ghostty.SurfaceView` (terminal surface, window membership checks)
- `Ghostty.SurfaceConfiguration` (workingDirectory, environmentVariables)
- `Ghostty.Notification` (ghosttyNewTab, ghosttyNewSplit, didEqualizeSplits, ghosttyFocusSplit, didToggleSplitZoom, didResizeSplit, NewSurfaceConfigKey, SplitDirectionKey, ResizeSplitDirectionKey, ResizeSplitAmountKey)
- `Ghostty.SplitFocusDirection` (toSplitTreeFocusDirection())
- `Ghostty.SplitResizeDirection` (up, down, left, right)
- `ghostty_action_split_direction_e` (GHOSTTY_SPLIT_DIRECTION_RIGHT/LEFT/DOWN/UP)
- `SplitTree` (inserting, removing, equalized, resizing, focusTarget, contains, isSplit, zoomed, viewBounds)
- `TerminalView`, `TerminalViewDelegate`, `TerminalSplitOperation`
- `AgentLauncher` (environmentVariables(for:))
- `AgentPresetsBar`
- `WorkspacePersistence`, `WindowState`, `WindowTabState`
- `WorkspaceSessionState`, `TabSessionState`, `SplitLayout`

### Integration Points
- `WorkspaceWindowController` is created by `AppDelegate` on app launch or via menu actions
- `restoreWindowTabs()` called on app launch to restore previous session
- `saveWindowTabState()` called on app quit and session save notifications
- `surfaceConfiguration(for:)` bridges workspace model to Ghostty terminal config
- Split delegate forwards all Ghostty core split notifications to the workspace surface tree
- Window controller intercepts `ghosttyNewTab` to create workspace tabs instead of terminal windows
- `NSWindow.tabbingMode = .automatic` enables native macOS tab bar

## Known Issues

1. **`showingGitPanel` declared but unused**: State property exists in `WorkspaceWindow` but is never referenced in the body.
2. **Window title uses emoji fallback**: `focusedSurfaceDidChange` uses ghost emoji string when title is empty, which may not render consistently.
3. **`createNativeTab` always passes `selectedWorkspaceID`**: New tabs inherit the parent's workspace ID, meaning you cannot create a tab for a different workspace from the current window.
4. **`restoreWindowTabs` iterates dictionary (unordered)**: Tab groups are reconstructed from `Dictionary` iteration which does not preserve original tab order.
5. **Race condition in `bindActiveViewModel`**: Uses `DispatchQueue.main.async` to find the window controller, which may fail if the window hierarchy is not yet established.
6. **Split delegate holds weak references**: `viewModel` and `workspaceID` can become nil between notification receipt and handling.
7. **`onNewSplit` accesses AppDelegate directly**: Uses `NSApplication.shared.delegate as? AppDelegate` cast which is fragile and not testable.
8. **`pwdDidChange` appends to command history**: Records `cd` commands but the actual command run by the user may differ.
9. **No graceful handling of missing Ghostty.App**: `WelcomeView` is shown but there is no retry or error messaging mechanism.

## Future Enhancements

- Remove unused `showingGitPanel` state or implement git panel integration
- Add workspace-specific tab creation (new tab in a different workspace)
- Preserve tab order during restoration by using an ordered collection
- Replace AppDelegate access in split delegate with dependency injection
- Add tab drag-and-drop between workspace windows
- Support tab pinning in native tab bar
- Add tab preview thumbnails
- Implement proper error handling for window restoration failures
- Add keyboard shortcuts for tab navigation within workspace

## Changelog

- 2026-03-20: Initial spec
