# Workspace Profiles

## Overview

Workspace Profiles group workspaces into switchable contexts, allowing users to focus on a subset of workspaces relevant to their current activity. A user might have a "Work" profile containing company repositories, a "Personal" profile with side projects, and a "Client A" profile with client-specific repos. Switching profiles filters the sidebar to show only that profile's workspaces. Workspaces can belong to multiple profiles or none (unassigned workspaces appear in all views). Profiles are persisted independently in `~/.ghostset/profiles.json` and the active profile is remembered across restarts.

## Architecture

### Key Files

| File | Role |
|------|------|
| `Sources/Features/Workspace/WorkspaceProfile.swift` (new) | `WorkspaceProfile` struct, `ProfileState`, `ProfilePersistence`, `ProfileManager` |
| `Sources/Features/Workspace/ProfileSwitcher.swift` (new) | SwiftUI dropdown in sidebar header for switching profiles |
| `Sources/Features/Workspace/ProfileManagerView.swift` (new) | SwiftUI sheet for profile CRUD and workspace assignment |
| `Sources/Features/Workspace/WorkspaceSidebar.swift` (modified) | Embed profile switcher, filter workspace list by active profile |
| `Sources/Features/Workspace/WorktreeManager.swift` (modified) | Own `ProfileManager`, expose filtered workspaces |
| `Sources/Features/Workspace/WorkspaceModel.swift` (no change) | Workspace struct unchanged; membership stored on profile side |

### Data Models

**WorkspaceProfile** (struct, Codable, Identifiable, Hashable — synthesized, all fields)

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `id` | `UUID` | auto-generated | Unique identifier |
| `name` | `String` | — | Display name (e.g., "Work", "Personal") |
| `iconName` | `String` | `"folder"` | SF Symbol name |
| `colorName` | `String` | `"blue"` | Named color for visual distinction |
| `workspaceIDs` | `Set<UUID>` | `[]` | Workspace IDs belonging to this profile |
| `sortOrder` | `Int` | `0` | Manual ordering in the profile switcher |
| `createdAt` | `Date` | now | Creation timestamp |

**ProfileState** (struct, Codable)

| Field | Type | Purpose |
|-------|------|---------|
| `version` | `Int` | Schema version (starts at 1) |
| `profiles` | `[WorkspaceProfile]` | All defined profiles |
| `activeProfileID` | `UUID?` | Currently active profile; `nil` = "All" view |
| `lastUpdated` | `Date` | Persistence timestamp |

**CRITICAL: Equatable/Hashable** — `WorkspaceProfile` must use compiler-synthesized conformances. Do NOT add id-only implementations — SwiftUI relies on full-field comparison to detect state changes (same lesson learned from template system).

### Feature Connections

| Connected Feature | Integration Point |
|-------------------|-------------------|
| `WorktreeManager` | Owns `ProfileManager`; exposes `filteredWorkspaces` |
| `WorkspaceSidebar` | Embeds `ProfileSwitcher` in header; reads `filteredWorkspaces` |
| `WorkspaceRow` | Context menu gains "Profiles" submenu |
| `NewWorkspaceSheet` | Optional profile picker for auto-assignment |
| `WorkspaceCommandPalette` | Filters results by active profile |

## Design Decisions

### Profile-Workspace Relationship

Membership stored **on the profile** (`workspaceIDs: Set<UUID>`), not on the workspace:

- **Many-to-many**: A workspace can appear in multiple profiles
- **No workspace mutation**: Adding to a profile doesn't modify `Workspace` struct or `state.json`
- **"Unassigned" semantics**: Workspaces not in any profile appear in every profile view (global workspaces)

### Separate Persistence

Profiles stored in `~/.ghostset/profiles.json`, separate from workspace state:
- Avoids write contention between profile and workspace operations
- Independent versioning and migration
- Simpler rollback if profile data corrupts

## UI Design

### Profile Switcher (sidebar header)

Replaces static "Workspaces" label with clickable dropdown:

```
┌────────────────────────────────┐
│ 💼 Work ▾  🔍 ↕ ⎇ + ▾        │
│────────────────────────────────│
│  ☐ All Workspaces        ✓    │
│  ──────────────────            │
│  💼 Work              (4)  ✓  │
│  🏠 Personal          (2)     │
│  🏢 Client A          (3)     │
│  ──────────────────            │
│  ⚙ Manage Profiles...         │
└────────────────────────────────┘
```

- Current profile: icon (colored) + name + chevron
- "All Workspaces": icon `tray.2`, shows all
- Per-profile: colored icon + name + workspace count + checkmark if active
- "Manage Profiles...": opens sheet

### Profile Manager View (sheet)

Two-panel layout:

```
┌──────────────────────────────────────────┐
│ Profiles                              +  │
├────────────┬─────────────────────────────┤
│ 💼 Work    │  Name: [Work          ]     │
│ 🏠 Personal│  Icon: 💼 🏠 🏢 💻 🌐 ⭐    │
│ 🏢 Client A│  Color: 🔵🟢🟠🔴🟣          │
│            │                             │
│            │  Workspaces:                │
│            │  ☑ ow-copilot               │
│            │  ☑ pv-map-tile-be           │
│            │  ☑ pv-map-tile-fe           │
│            │  ☐ blog                     │
│            │  ☐ dotfiles                 │
│            │                             │
│ + —        │  [Delete Profile]           │
├────────────┴─────────────────────────────┤
│                                   [Done] │
└──────────────────────────────────────────┘
```

### Context Menu Assignment

In workspace right-click menu, between "Tags" and "Settings...":

```
Profiles ▸  ☑ Work
            ☐ Personal
            ☑ Client A
            ──────────
            Manage Profiles...
```

### Sidebar Filtering Behavior

When a profile is active:
1. Show workspaces in the profile's `workspaceIDs`
2. Also show workspaces not assigned to ANY profile (unassigned = global)
3. Search, tag, and archive filters still apply on top
4. Sort order preserved

When "All Workspaces" is active:
- Show all workspaces (current behavior)

## JSON Format

### profiles.json

```json
{
  "version": 1,
  "activeProfileID": "550e8400-e29b-41d4-a716-446655440001",
  "lastUpdated": "2026-03-24T14:30:00Z",
  "profiles": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "name": "Work",
      "iconName": "briefcase",
      "colorName": "blue",
      "workspaceIDs": [
        "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "e5f6g7h8-i9j0-1234-abcd-ef5678901234"
      ],
      "sortOrder": 0,
      "createdAt": "2026-03-20T10:00:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440002",
      "name": "Personal",
      "iconName": "house",
      "colorName": "green",
      "workspaceIDs": [
        "i9j0k1l2-m3n4-5678-abcd-ef9012345678"
      ],
      "sortOrder": 1,
      "createdAt": "2026-03-20T10:05:00Z"
    }
  ]
}
```

### Minimal Example

```json
{
  "version": 1,
  "profiles": [
    {
      "name": "Work",
      "iconName": "briefcase",
      "colorName": "blue",
      "workspaceIDs": []
    }
  ]
}
```

## Implementation Plan

### Phase 1: Data Model and Persistence
1. Create `WorkspaceProfile.swift` — struct, `ProfileState`, `ProfilePersistence`, `ProfileManager`
2. Integrate into `WorktreeManager` — own `ProfileManager`, expose `filteredWorkspaces`
3. Clean up deleted workspace IDs from profiles in `deleteWorkspace()` and `untrackWorkspace()`

### Phase 2: Profile Switcher UI
4. Create `ProfileSwitcher.swift` — dropdown Menu in sidebar header
5. Embed in `WorkspaceSidebar` — replace "Workspaces" label, filter workspace list

### Phase 3: Profile Management
6. Create `ProfileManagerView.swift` — two-panel sheet with CRUD and workspace assignment

### Phase 4: Integration
7. Add "Profiles" submenu to workspace context menu
8. Add profile picker to `NewWorkspaceSheet`
9. Profile indicators on `WorkspaceRow` (small colored dots)

### Phase 5: Polish
10. Command palette filtering by active profile
11. Keyboard shortcut: Cmd+Shift+P cycles profiles
12. Orphan ID pruning on profile load

## Known Constraints

1. **Naming overlap**: `EnvironmentProfile` already exists. New type is `WorkspaceProfile`.
2. **No nested profiles**: Flat structure only. Hierarchical grouping is a future enhancement.
3. **No per-profile windows**: All profiles share the same window.
4. **Unassigned visibility**: Workspaces not in any profile appear in all views. This prevents accidental hiding but may confuse users expecting strict isolation.

## Future Enhancements

1. Profile-specific settings (default agent, template, environment)
2. Hierarchical profiles (nested groups)
3. Profile sharing (export/import JSON)
4. Per-profile windows
5. Auto-assignment rules (repo path patterns → profile)
6. Profile-scoped keyboard shortcuts (Cmd+1/2/3)
7. Hide unassigned toggle per profile
8. Profile-aware notifications (mute inactive profiles)

## Changelog

- 2026-03-24: Initial design document
