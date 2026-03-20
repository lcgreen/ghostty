# Workspace Persistence

## Overview

The workspace persistence system handles serialization of all workspace state to disk, ensuring workspaces, tag definitions, environment profiles, terminal session layouts, and window tab configurations survive app restarts. The system uses three storage locations: `~/.ghostset/state.json` for global workspace state, `~/.ghostset/sessions/{uuid}.json` for per-workspace terminal session layouts, and `~/.ghostset/window-state.json` for native window tab restoration. The `WorkspaceModel.swift` file defines the core data types used throughout the system.

## Architecture

### Key Files

| File | Role |
|------|------|
| `Sources/Features/Workspace/WorkspacePersistence.swift` | `WorkspacePersistence` class, `PersistedState`, `WindowState`, `WindowTabState` structs |
| `Sources/Features/Workspace/WorkspaceModel.swift` | `Workspace`, `WorkspaceStatus`, `EnvironmentProfile`, `WorkspaceConfig`, `WorkspaceChangeStats`, `WorkspaceSortOrder`, `WorkspaceFilter` types |

### Data Models

#### WorkspaceModel.swift

**Workspace** (struct, Identifiable, Codable, Hashable)
- `id: UUID` -- unique identifier, generated on creation
- `name: String` -- mutable display name
- `repoPath: String` -- path to the git repository
- `worktreePath: String` -- path to this workspace's worktree directory
- `branch: String` -- git branch name
- `createdAt: Date` -- creation timestamp
- `agent: AgentType?` -- optional agent type
- `status: WorkspaceStatus` -- current lifecycle status (initial: `.creating`)
- `tags: [String]` -- tag labels
- `taskDescription: String?` -- optional task description
- `isPinned: Bool` -- whether workspace is pinned to top (default: `false`)
- `isArchived: Bool` -- whether workspace is archived (default: `false`)
- `sortOrder: Int` -- manual sort position (default: `0`)

Workspace methods:
- `renamed(to:) -> Workspace` -- returns copy with new name
- `toggledPin() -> Workspace` -- returns copy with `isPinned` toggled
- `toggledArchive() -> Workspace` -- returns copy with `isArchived` toggled
- `hash(into:)` -- hashes by `id`
- `==` -- compares by `id`
- Custom `init(from decoder:)` -- backward-compatible decoding with defaults for `tags` (empty), `taskDescription` (nil), `isPinned` (false), `isArchived` (false), `sortOrder` (0)

**WorkspaceStatus** (enum, Codable, Equatable)
| Case | displayLabel | iconName | iconColor |
|------|-------------|----------|-----------|
| `.creating` | "Creating..." | "circle.dotted" | "secondary" |
| `.ready` | "Ready" | "circle" | "blue" |
| `.running(pid: Int32)` | "Running" | "circle.fill" | "green" |
| `.stopped` | "Stopped" | "stop.circle" | "gray" |
| `.error(String)` | "Error: {msg}" | "exclamationmark.circle" | "red" |

Computed property: `isActive: Bool` -- true only for `.running`

**EnvironmentProfile** (struct, Codable, Identifiable, Hashable)
- `id: UUID`, `name: String`, `variables: [String: String]`, `colorName: String`
- Static `presets`: Development (green), Staging (orange), Production (red)

**WorkspaceConfig** (struct, Codable)
- `defaultAgent: AgentType?`, `setupCommand: String?`, `teardownCommand: String?`
- `environmentVariables: [String: String]`, `shell: String?`, `workingDirectory: String?`
- `environmentProfiles: [EnvironmentProfile]?`, `activeProfileID: UUID?`
- Computed: `activeProfile` (looks up by ID), `effectiveEnvironmentVariables` (merges base + active profile)

**WorkspaceChangeStats** (struct, Equatable)
- `additions: Int`, `deletions: Int`, `filesChanged: Int`
- Static `zero` constant
- `summary: String` -- e.g., "+5 -3" or "No changes"

**WorkspaceSortOrder** (enum, String, CaseIterable, Codable)
| Case | Raw Value | System Image |
|------|-----------|-------------|
| `.manual` | "Manual" | "hand.draw" |
| `.name` | "Name" | "textformat.abc" |
| `.dateCreated` | "Date Created" | "calendar" |
| `.status` | "Status" | "circle.fill" |
| `.changeCount` | "Changes" | "plus.forwardslash.minus" |

**WorkspaceFilter** (enum, String, CaseIterable)
| Case | Raw Value | System Image |
|------|-----------|-------------|
| `.active` | "Active" | "tray.full" |
| `.archived` | "Archived" | "archivebox" |
| `.all` | "All" | "tray.2" |

#### WorkspacePersistence.swift

**PersistedState** (private struct, Codable)
- `version: Int` -- schema version (current: 4)
- `lastUpdated: Date`
- `workspaces: [Workspace]`
- `tagDefinitions: [TagDefinition]?`
- `cleanShutdown: Bool?`
- `environmentProfiles: [EnvironmentProfile]?`
- `activeProfileID: UUID?`

**WindowState** (struct, Codable)
- `tabs: [WindowTabState]` -- ordered list of window tabs
- `savedAt: Date` -- auto-set on init

**WindowTabState** (struct, Codable)
- `selectedWorkspaceID: UUID?` -- nil means blank terminal
- `splitLayout: SplitLayout?` -- terminal split configuration
- `title: String?` -- custom tab title
- `agent: AgentType?` -- agent running in this tab
- `agentSessionID: String?` -- agent-specific session ID for resume

### Feature Connections

- **WorktreeManager** -- primary consumer, calls load/save for workspaces, tags, profiles
- **WorkspaceWindowController** -- saves and restores window tab state
- **TagDefinition** -- persisted alongside workspaces in state.json
- **SplitLayout** -- serialized terminal split tree layout
- **WorkspaceSessionState** / **TabSessionState** -- per-workspace multi-tab session data (defined elsewhere)

## Current Implementation

### WorkspacePersistence Properties

| Property | Type | Value |
|----------|------|-------|
| `statePath` | `String` (private) | `~/.ghostset/state.json` |
| `sessionsDir` | `String` (private computed) | `~/.ghostset/sessions` |
| `windowStatePath` | `String` (private computed) | `~/.ghostset/window-state.json` |
| `encoder` | `JSONEncoder` (private) | Pretty-printed, sorted keys, ISO 8601 dates |
| `decoder` | `JSONDecoder` (private) | ISO 8601 dates |

### WorkspacePersistence Methods

**Workspace State**

| Method | Signature | Purpose |
|--------|-----------|---------|
| `load()` | `func load() -> [Workspace]` | Loads workspaces from `state.json`. Returns empty array on missing file or decode error. Logs decode errors to stdout. |
| `save(_:tagDefinitions:)` | `func save(_ workspaces: [Workspace], tagDefinitions: [TagDefinition]? = nil)` | Saves workspaces to `state.json`. Preserves existing tag definitions if not explicitly provided. Also preserves existing environment profiles and active profile ID by reloading them. Creates `~/.ghostset/` directory if needed. |

**Tag Definitions**

| Method | Purpose |
|--------|---------|
| `loadTagDefinitions()` | Loads tag definitions from `state.json`. Returns `TagDefinition.presets` on missing file, decode error, or empty result. |
| `saveTagDefinitions(_:)` | Saves tag definitions by reloading workspaces and calling `save()` with both. |

**Environment Profiles**

| Method | Purpose |
|--------|---------|
| `loadEnvironmentProfiles()` | Loads profiles from `state.json`. Returns empty array on failure. |
| `loadActiveProfileID()` | Loads active profile UUID from `state.json`. Returns nil on failure. |
| `saveEnvironmentProfiles(_:activeProfileID:)` | Saves profiles by reloading workspaces and tags, then writing full state. Sets profiles to nil if empty. |

**Session State**

| Method | Purpose |
|--------|---------|
| `saveSession(_:)` | Saves `WorkspaceSessionState` to `~/.ghostset/sessions/{uuid}.json`. Creates sessions directory if needed. |
| `loadSession(workspaceID:)` | Loads `WorkspaceSessionState` from `~/.ghostset/sessions/{uuid}.json`. Returns nil on failure. |
| `removeSession(workspaceID:)` | Deletes the session file for a workspace. |

**Window State**

| Method | Purpose |
|--------|---------|
| `saveWindowState(_:)` | Saves `WindowState` to `~/.ghostset/window-state.json`. Creates directory if needed. |
| `loadWindowState()` | Loads `WindowState` from `~/.ghostset/window-state.json`. Returns nil on failure. |

### Storage File Formats

**~/.ghostset/state.json**
```json
{
  "version": 4,
  "lastUpdated": "2026-03-20T...",
  "workspaces": [...],
  "tagDefinitions": [...],
  "cleanShutdown": true,
  "environmentProfiles": [...],
  "activeProfileID": "uuid-string"
}
```

**~/.ghostset/sessions/{uuid}.json**
```json
{
  "workspaceID": "uuid-string",
  "tabs": [
    { "title": "Shell", "splitLayout": {...}, "agent": null, "sessionID": null }
  ],
  "activeTabIndex": 0
}
```

**~/.ghostset/window-state.json**
```json
{
  "tabs": [
    { "selectedWorkspaceID": "uuid-string", "splitLayout": null, "title": null, "agent": null, "agentSessionID": null }
  ],
  "savedAt": "2026-03-20T..."
}
```

## Design Consistency

This feature has no UI -- it is a pure persistence layer. Consistency concerns:

| Aspect | Pattern |
|--------|---------|
| Encoding | Pretty-printed JSON with sorted keys, ISO 8601 dates |
| Error handling | Print to stdout, return empty/default values |
| Directory creation | `createDirectory(withIntermediateDirectories: true)` |
| File location | All under `~/.ghostset/` |
| Versioning | `PersistedState.currentVersion = 4` |

## Ghostty Codebase Alignment

### Types Used
- `Workspace` (Codable struct with backward-compatible decoder)
- `WorkspaceStatus` (Codable enum with associated values)
- `AgentType` (Codable, used in Workspace, WindowTabState)
- `TagDefinition` (Codable, loaded/saved alongside workspaces)
- `EnvironmentProfile` (Codable, persisted in state.json)
- `SplitLayout` (Codable, serialized terminal split configuration)
- `WorkspaceSessionState` / `TabSessionState` (Codable, per-workspace session data)

### Integration Points
- `WorktreeManager` calls `load()` on init and `save()` after every workspace mutation
- `WorkspaceWindowController.saveWindowTabState()` calls `saveWindowState()` and `saveSession()`
- `WorkspaceWindowController.restoreWindowTabs()` calls `loadWindowState()`
- `WorkspaceWindow.saveAllSessions()` iterates all tab groups and saves session state
- App delegate triggers save on `applicationWillTerminate` and `applicationDidResignActive`

## Known Issues

1. **Non-atomic writes**: `data.write(to:)` is not atomic -- a crash during write could corrupt the file. Should use `Data.WritingOptions.atomic`.
2. **Full state reload on partial save**: `save()`, `saveTagDefinitions()`, and `saveEnvironmentProfiles()` all reload the entire state from disk before saving, creating race conditions if called concurrently.
3. **No file locking**: Multiple WorkspacePersistence instances (they are value-like, created ad-hoc) can read/write simultaneously without coordination.
4. **No migration system**: `PersistedState.currentVersion` is set to 4 but there is no migration logic for older versions -- just backward-compatible decoding with defaults.
5. **Error handling prints to stdout**: Uses `print()` for errors instead of structured logging with `os.Logger`.
6. **Session files not cleaned up**: `removeSession()` is available but session files for deleted workspaces may accumulate if not explicitly called.
7. **Window state and session state are redundant**: Both `window-state.json` and per-workspace session files track similar tab/split information, with `window-state.json` noted as "backward compat".
8. **No backup mechanism**: No automatic backup before overwriting state files.

## Future Enhancements

- Use atomic file writes (`Data.WritingOptions.atomic`)
- Add file locking or serialize all persistence operations through an actor
- Implement state migration system for version upgrades
- Replace `print()` error logging with `os.Logger`
- Add automatic backup rotation (keep last N state files)
- Clean up orphaned session files on startup
- Consolidate window-state.json and session files into a single persistence format
- Add data integrity checksums
- Support iCloud sync for workspace state
- Add export/import of full workspace state for machine migration

## Changelog

- 2026-03-20: Initial spec
