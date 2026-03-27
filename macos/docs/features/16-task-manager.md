# Task Manager

## Overview

The Task Manager provides a background task queue for long-running operations that currently block the UI or run fire-and-forget with no visibility. Operations like worktree creation/deletion, lifecycle commands, git operations, and template application all involve shell processes that can take seconds or fail silently. The Task Manager gives these operations structure: queuing, progress tracking, cancellation, error handling, and a compact UI showing what's happening.

## Problem Statement

Current issues:
- **Worktree deletion** hangs while `git worktree remove` runs — user sees "Deleting..." status but no progress
- **Lifecycle commands** (`onCreateCommand`/`onDestroyCommand`) run fire-and-forget on background threads with errors only logged
- **Workspace creation** blocks with `isCreating = true` flag but no cancellation
- **Template application** uses hardcoded delays (`asyncAfter 0.5s`, `1.0s`) that are race-prone
- **Branch validation** runs inline, adding latency to the creation flow
- **Multiple operations** can conflict (e.g., deleting a workspace while its lifecycle command is still running)

## Design Goals

1. **Non-blocking** — all long-running operations run in the background via structured concurrency
2. **Visible** — compact status bar shows active/recent tasks with progress
3. **Cancellable** — user can cancel long-running operations
4. **Sequential where needed** — operations on the same workspace are serialized
5. **Error surfacing** — failures shown inline, not just logged to console
6. **Minimal UI** — small indicator in sidebar footer, expandable to see details

## Architecture

### Key Files

| File | Role |
|------|------|
| `Sources/Features/Workspace/TaskManager.swift` (new) | `WorkspaceTask`, `TaskManager` (ObservableObject), task queue and execution |
| `Sources/Features/Workspace/TaskStatusBar.swift` (new) | Compact SwiftUI bar showing active/recent tasks |
| `Sources/Features/Workspace/WorkspaceSidebar.swift` (modified) | Embed `TaskStatusBar` at sidebar bottom |
| `Sources/Features/Workspace/WorktreeManager.swift` (modified) | Route operations through `TaskManager` |

### Data Models

**WorkspaceTask** (class, Identifiable, ObservableObject)

| Field | Type | Purpose |
|-------|------|---------|
| `id` | `UUID` | Unique identifier |
| `title` | `String` | Human-readable description (e.g., "Deleting worktree...") |
| `workspaceID` | `UUID?` | Associated workspace (for serialization) |
| `status` | `TaskStatus` | `.pending`, `.running`, `.completed`, `.failed(String)`, `.cancelled` |
| `progress` | `Double?` | Optional 0.0–1.0 progress (nil = indeterminate) |
| `createdAt` | `Date` | When the task was queued |
| `task` | `Task<Void, Never>?` | The Swift concurrency task handle (for cancellation) |

**TaskStatus** (enum)

| Case | Meaning |
|------|---------|
| `.pending` | Queued, waiting to run |
| `.running` | Currently executing |
| `.completed` | Finished successfully |
| `.failed(String)` | Failed with error message |
| `.cancelled` | Cancelled by user |

**TaskManager** (ObservableObject)

| Property | Type | Purpose |
|----------|------|---------|
| `activeTasks` | `[WorkspaceTask]` | Currently running/pending tasks |
| `recentTasks` | `[WorkspaceTask]` | Last N completed/failed tasks (auto-cleared after 30s) |
| `hasActiveTasks` | `Bool` | Quick check for UI indicator |

Methods:
- `enqueue(title:workspaceID:operation:) -> WorkspaceTask` — add task to queue
- `cancel(taskID:)` — cancel a running task
- `clearCompleted()` — remove finished tasks from recent list

### Operations to Route Through TaskManager

| Operation | Current Location | Current Behavior |
|-----------|-----------------|------------------|
| Create worktree | `WorktreeManager.createWorkspace()` | Blocks with `isCreating` flag |
| Delete worktree | `WorktreeManager.deleteWorkspace()` | Async but errors swallowed |
| Lifecycle commands | `WorktreeManager.runLifecycleCommand()` | Fire-and-forget, errors logged |
| Apply template | `WorkspaceViewModelCache.applyTemplate()` | Runs on main thread with delays |
| Branch validation | `WorktreeManager.branchExists()` | Inline async check |
| Git operations | `GitStatusPanel` stage/commit/push | Individual async calls |

## UI Design

### Task Status Bar (sidebar footer)

Compact bar above the existing footer, only visible when tasks exist:

```
┌──────────────────────────────────────┐
│ ⟳ Deleting worktree...          ✕   │
│ ✓ Created "feature-x"     2s ago    │
└──────────────────────────────────────┘
```

- **Active task**: spinner + title + cancel button
- **Recent completed**: checkmark (green) + title + time ago
- **Recent failed**: exclamation (red) + title + error (truncated) + retry button
- Auto-hides completed tasks after 30 seconds
- Click to expand full task list

### Sidebar Integration

```
┌─────────────────────────┐
│ 💼 Work ▾  🔍 ↕ + ▾     │  ← Profile switcher
│─────────────────────────│
│ workspace1              │
│ workspace2              │
│ workspace3              │
│─────────────────────────│
│ ⟳ Creating worktree...  │  ← Task status bar
└─────────────────────────┘
```

## Implementation Plan

### Phase 1: Core TaskManager
1. Create `WorkspaceTask` and `TaskManager`
2. Queue management with workspace-level serialization
3. Auto-cleanup of completed tasks

### Phase 2: Route Operations
4. Wrap `createWorkspace` in a task
5. Wrap `deleteWorkspace` in a task
6. Wrap `runLifecycleCommand` in a task
7. Remove hardcoded delays from template application

### Phase 3: UI
8. Create `TaskStatusBar` view
9. Embed in sidebar
10. Add cancel and retry actions

### Phase 4: Polish
11. Error surfacing with retry
12. Task history (last 10 operations)
13. Conflict detection (warn if operating on same workspace)

## Known Constraints

1. **Swift concurrency model** — operations must be `@Sendable` closures; some existing code uses `DispatchQueue` patterns that need migration
2. **Main thread requirement** — SwiftUI state updates must happen on `@MainActor`; task completions need to dispatch to main
3. **Process lifecycle** — `Process` objects (git commands) don't support cooperative cancellation; cancelling a task may leave orphaned processes

## Future Enhancements

1. Task notifications (macOS notification on completion/failure)
2. Task log export for debugging
3. Parallel task execution with dependency graph
4. Task templates (common operation sequences)
5. Persistent task history across app restarts

## Changelog

- 2026-03-25: Initial design document
