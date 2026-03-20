# Notifications

## Overview

WorkspaceNotifier is an `ObservableObject` that monitors workspace terminal activity and delivers macOS notifications when background agents appear idle or when error patterns are detected in terminal output. It maintains unread badges per workspace, a capped notification history (50 entries), and configurable idle detection with a default 10-second threshold. The system uses `UNUserNotificationCenter` for native macOS notifications with a custom "SWITCH_WORKSPACE" action category.

## Architecture

### Key Files

| File | Role |
|------|------|
| `Sources/Features/Workspace/WorkspaceNotifier.swift` | Full implementation: activity tracking, error detection, notification delivery, history |

### Data Models

**ActivityState** (struct, nested in WorkspaceNotifier)
- `lastOutputTime: Date?` -- timestamp of most recent terminal output
- `wasActive: Bool` -- whether the workspace had recent activity (default: `false`)
- `notifiedIdle: Bool` -- whether an idle notification was already sent (default: `false`)

**NotificationCategory** (enum, String, nested in WorkspaceNotifier)
| Case | Raw Value | Sound |
|------|-----------|-------|
| `.agentFinished` | `"agent_finished"` | `.default` |
| `.errorDetected` | `"error_detected"` | `.defaultCritical` |
| `.buildComplete` | `"build_complete"` | `.default` |
| `.general` | `"general"` | `.default` |

**NotificationEntry** (struct, Identifiable, nested in WorkspaceNotifier)
- `id: UUID` -- auto-generated
- `title: String` -- notification title
- `body: String` -- notification body
- `category: NotificationCategory` -- event type
- `workspaceID: UUID` -- associated workspace
- `timestamp: Date` -- when the notification was created

### Feature Connections

- **Workspace** -- provides `id`, `name`, `agent` for notification content
- **AgentType** -- `displayName` used in idle notification body
- **UNUserNotificationCenter** -- macOS notification delivery
- **os.Logger** -- structured logging under subsystem `com.mitchellh.ghostty`, category `workspace-notifier`

## Current Implementation

### Published Properties

| Property | Type | Purpose |
|----------|------|---------|
| `unreadWorkspaces` | `@Published Set<UUID>` | Set of workspace IDs with unread activity |
| `notificationHistory` | `@Published [NotificationEntry]` | Ordered list of notification entries (newest first) |

### Configuration Properties

| Property | Type | Default | Storage |
|----------|------|---------|---------|
| `idleThreshold` | `TimeInterval` (get/set) | 10 seconds | UserDefaults key `ghostset.idleThreshold`, clamped to 5-300 seconds |

### Private State

| Property | Type | Purpose |
|----------|------|---------|
| `activityStates` | `[UUID: ActivityState]` | Per-workspace activity tracking |
| `selectedWorkspaceID` | `UUID?` | Currently viewed workspace (notifications suppressed for this) |
| `timer` | `Timer?` | Repeating timer for idle checking |
| `maxHistoryEntries` | `Int` (constant: 50) | Maximum notification history size |

### Error Detection Patterns

The following string patterns are checked against terminal output:
```
"error:", "Error:", "ERROR:", "fatal:", "Fatal:",
"panic:", "PANIC:", "exception:", "Exception:",
"FAILED", "segfault", "Segmentation fault"
```

### Logger

```swift
private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
    category: "workspace-notifier"
)
```

### Methods

**Initialization**

| Method | Purpose |
|--------|---------|
| `init()` | Calls `requestPermission()` and `registerCategories()` |
| `requestPermission()` | Requests `.alert`, `.sound`, `.badge` authorization via `UNUserNotificationCenter` |
| `registerCategories()` | Registers a `UNNotificationCategory` with identifier `"WORKSPACE_EVENT"` containing a single action: `SWITCH_WORKSPACE` ("Switch to Workspace", `.foreground` option) |

**Activity Tracking**

| Method | Signature | Purpose |
|--------|-----------|---------|
| `recordActivity(workspaceID:output:)` | `func recordActivity(workspaceID: UUID, output: String? = nil)` | Updates `ActivityState` for workspace: sets `lastOutputTime` to now, marks `wasActive = true`, resets `notifiedIdle = false`. Adds workspace to `unreadWorkspaces` if not currently selected. If output is provided and workspace is not selected, calls `detectErrors(in:workspaceID:)`. |
| `markRead(workspaceID:)` | `func markRead(workspaceID: UUID)` | Sets `selectedWorkspaceID` and removes workspace from `unreadWorkspaces` |
| `checkForIdleAgents(workspaces:)` | `func checkForIdleAgents(workspaces: [Workspace])` | Iterates workspaces with agents. For each workspace where: agent is non-nil, `wasActive` is true, `notifiedIdle` is false, and time since `lastOutputTime` exceeds `idleThreshold` -- marks idle, sends `.agentFinished` notification, adds to `unreadWorkspaces`. |

**Error Detection**

| Method | Purpose |
|--------|---------|
| `detectErrors(in:workspaceID:)` | Scans output string for any of the 11 error patterns. On first match, sends an `.errorDetected` notification with title "Error Detected" and body "Terminal output contains: {pattern}". Breaks after first match. |

**Monitoring Control**

| Method | Purpose |
|--------|---------|
| `startMonitoring(workspaces:)` | Invalidates existing timer, starts new repeating `Timer` with 5-second interval calling `checkForIdleAgents(workspaces:)`. Note: the workspace list is captured at start time and not refreshed. |
| `stopMonitoring()` | Invalidates and nils the timer |

**History Management**

| Method | Purpose |
|--------|---------|
| `clearHistory()` | Removes all entries from `notificationHistory` |

**Notification Delivery**

| Method | Purpose |
|--------|---------|
| `sendNotification(title:body:category:workspaceID:)` | (1) Creates `NotificationEntry` and inserts at index 0 of `notificationHistory` on main thread, trimming to `maxHistoryEntries`. (2) Creates `UNMutableNotificationContent` with title, body, category sound, `"WORKSPACE_EVENT"` category identifier, and userInfo containing `workspaceID` (as UUID string) and `category` (as raw value). (3) Creates `UNNotificationRequest` with identifier `"ghostset-{uuid}-{timestamp}"` and nil trigger (immediate delivery). (4) Adds request via `UNUserNotificationCenter.current().add()`. |

### Double Extension

```swift
private extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double
}
```
Returns `defaultValue` if value is 0, otherwise clamps to range bounds.

### Notification Content Structure

Each macOS notification contains:
- `content.title` -- workspace name or "Error Detected"
- `content.body` -- descriptive message
- `content.sound` -- `.default` or `.defaultCritical` (for errors)
- `content.categoryIdentifier` -- `"WORKSPACE_EVENT"`
- `content.userInfo["workspaceID"]` -- UUID string
- `content.userInfo["category"]` -- category raw value string

## Design Consistency

This feature has no UI elements of its own -- it is a pure data/notification service. UI integration points:

| Consumer | Usage |
|----------|-------|
| Workspace sidebar | Reads `unreadWorkspaces` to show badge indicators |
| Notification history view | Reads `notificationHistory` for display |
| Workspace selection | Calls `markRead(workspaceID:)` to clear badges |

## Ghostty Codebase Alignment

### Types Used
- `Workspace` (id, name, agent)
- `AgentType` (displayName)
- `os.Logger` with Bundle.main.bundleIdentifier subsystem
- `UNUserNotificationCenter`, `UNMutableNotificationContent`, `UNNotificationRequest`, `UNNotificationAction`, `UNNotificationCategory`

### Integration Points
- Owned by `WorktreeManager` or the workspace window coordinator
- `recordActivity()` called when terminal output is detected
- `markRead()` called when user switches to a workspace
- `startMonitoring()` / `stopMonitoring()` called on app lifecycle events
- `unreadWorkspaces` observed by sidebar for badge display
- macOS notification tap with `SWITCH_WORKSPACE` action handled by `UNUserNotificationCenterDelegate` (not implemented in this file)

## Known Issues

1. **`startMonitoring` captures workspace list at call time**: The timer closure captures the initial `workspaces` array. New workspaces created after monitoring starts will not be checked for idle until `startMonitoring` is called again.
2. **No `UNUserNotificationCenterDelegate` implementation**: The `SWITCH_WORKSPACE` notification action is registered but there is no delegate to handle user taps on the notification action.
3. **Error detection is substring-based**: Simple `String.contains()` matching produces false positives (e.g., "error:" in a URL or log message that is not actually an error).
4. **No rate limiting on error notifications**: Rapid terminal output with error patterns can generate a flood of notifications.
5. **Timer runs on main thread**: `Timer.scheduledTimer` runs on the main run loop, though the actual work is lightweight.
6. **`notificationHistory` mutation on main thread via DispatchQueue**: Uses `DispatchQueue.main.async` for thread safety but `sendNotification` itself can be called from any thread.
7. **No notification grouping**: Multiple notifications from the same workspace are not grouped in macOS Notification Center.
8. **`buildComplete` category is defined but never used**: No code path sends a `.buildComplete` notification.

## Future Enhancements

- Implement `UNUserNotificationCenterDelegate` to handle notification action taps
- Add notification rate limiting (e.g., max 1 per workspace per 30 seconds)
- Make error patterns configurable per workspace
- Add regex-based pattern matching for more precise error detection
- Refresh workspace list on timer tick instead of capturing at start
- Add notification preferences per workspace (enable/disable, sound selection)
- Implement `.buildComplete` detection for common build tools (make, cargo, npm, etc.)
- Add notification grouping by workspace in macOS Notification Center
- Support custom notification sounds
- Add "Do Not Disturb" mode

## Changelog

- 2026-03-20: Initial spec
