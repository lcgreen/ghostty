# Workspace Settings

## Overview

WorkspaceSettingsPopover is a per-workspace configuration panel presented as a popover (320x480). It provides environment profile management with a global profile switcher, setup/teardown command configuration with inline execution, shell selection, working directory override, and workspace path/branch information display. Settings are persisted per-repository in `{repoPath}/.ghostset/config.json`. The profile editor sheet enables full key-value environment variable management with quick-add presets.

## Architecture

### Key Files

| File | Role |
|------|------|
| `Sources/Features/Workspace/WorkspaceSettingsPopover.swift` | Main popover view + `ProfileEditorSheet` sub-view |
| `Sources/Features/Workspace/WorkspaceModel.swift` | `EnvironmentProfile`, `WorkspaceConfig` models |

### Data Models

**EnvironmentProfile** (struct, Codable, Identifiable, Hashable) -- defined in WorkspaceModel.swift
- `id: UUID` -- unique identifier
- `name: String` -- profile display name
- `variables: [String: String]` -- key-value environment variables
- `colorName: String` -- color identifier (default: `"blue"`)

**WorkspaceConfig** (struct, Codable) -- defined in WorkspaceModel.swift
- `defaultAgent: AgentType?` -- default agent for new terminals
- `setupCommand: String?` -- shell command to run on workspace setup
- `teardownCommand: String?` -- shell command to run on workspace teardown
- `environmentVariables: [String: String]` -- base environment variables
- `shell: String?` -- shell override path
- `workingDirectory: String?` -- subdirectory override
- `environmentProfiles: [EnvironmentProfile]?` -- per-repo profiles (unused in this view)
- `activeProfileID: UUID?` -- active profile ID (unused in this view)
- Computed: `activeProfile: EnvironmentProfile?`, `effectiveEnvironmentVariables: [String: String]`

**EnvironmentProfile.presets** (static)
| Name | Variables | Color |
|------|-----------|-------|
| "Development" | NODE_ENV=development, DEBUG=*, LOG_LEVEL=debug | green |
| "Staging" | NODE_ENV=staging, LOG_LEVEL=info | orange |
| "Production" | NODE_ENV=production, LOG_LEVEL=warn | red |

### Feature Connections

- **WorktreeManager** -- manages global environment profiles via `environmentProfiles`, `activeProfileID`, `activeProfile`, `upsertEnvironmentProfile()`, `removeEnvironmentProfile()`, `setActiveProfile()`
- **Workspace** -- provides `worktreePath`, `repoPath`, `branch` for display and config storage
- **TagDefinition** -- provides `swiftUIColor(for:)` for profile color rendering
- **FlowLayout** -- custom layout container for profile pills

## Current Implementation

### WorkspaceSettingsPopover State Properties

| Property | Type | Purpose |
|----------|------|---------|
| `manager` | `@ObservedObject WorktreeManager` | Global profile and workspace management |
| `workspace` | `Workspace` | The workspace being configured (let, not binding) |
| `editingProfile` | `@State EnvironmentProfile?` | Profile currently open in editor sheet |
| `showingNewProfile` | `@State Bool` | Whether new profile form is visible |
| `newProfileName` | `@State String` | Name field for new profile |
| `newProfileColor` | `@State String` | Color selection for new profile (default: `"blue"`) |
| `setupCommand` | `@State String` | Setup command text |
| `teardownCommand` | `@State String` | Teardown command text |
| `selectedShell` | `@State String` | Selected shell (default: `"Default"`) |
| `workingDirectory` | `@State String` | Working directory override |
| `showRunConfirm` | `@State Bool` | Whether the run confirmation alert is shown |
| `commandOutput` | `@State String?` | Output from running the setup command |

### Constants

| Constant | Value |
|----------|-------|
| `shellOptions` | `["Default", "/bin/zsh", "/bin/bash", "/usr/local/bin/fish", "/usr/bin/env nushell"]` |

### WorkspaceSettingsPopover UI Elements

**Title**
- "Workspace Settings" -- `.system(size: 12, weight: .semibold)`

**Profile Switcher** (`profileSwitcher`)
- Section header: "Environment" with add button (`plus` icon, `.system(size: 9)`)
- Empty state: "No profiles" text (`.system(size: 10)`, `.tertiary`) + "Add Presets" button (`.system(size: 10)`, `.bordered`, `.controlSize(.mini)`) that loads `EnvironmentProfile.presets`
- Profile pills (`FlowLayout`, spacing 4): Each pill shows colored dot (6x6), name (`.system(size: 10)`), variable count (`.system(size: 8)`, `.tertiary`). Active pill has semibold text, colored background (`.opacity(0.15)`), colored border (`.opacity(0.3)`). Inactive pill has `.primary.opacity(0.04)` background. Context menu: Edit, Duplicate, Delete.
- Active profile detail (`activeProfileDetail`): Shows colored dot (5x5), profile name (`.system(size: 10, weight: .semibold)`), "active" badge with profile color, "Edit" button. Lists sorted key=value pairs in monospaced font (`.system(size: 9)`). Background: `.primary.opacity(0.02)`, cornerRadius 5.

**New Profile Form** (`newProfileForm`)
- Title: "New Profile" (`.system(size: 10, weight: .semibold)`, `.secondary`)
- Name field: `TextField("Profile name")`, `.roundedBorder`, `.system(size: 11)`
- Color picker: 6 circles (12x12) for green, orange, red, blue, purple, teal. Selected circle has white 1.5pt stroke border.
- Cancel button: `.system(size: 10)`, `.plain`, `.secondary`
- Create button: `.system(size: 10)`, `.borderedProminent`, `.controlSize(.mini)`, disabled when name is empty/whitespace
- Background: `.primary.opacity(0.03)`, cornerRadius 5

**Command Sections** (`commandSection(title:text:runnable:)`)
- Section header: uppercase text (`.system(size: 9, weight: .medium)`, `.tertiary`)
- Text field: `TextField("e.g., npm install")`, `.plain`, `.system(size: 10, design: .monospaced)`, with `.primary.opacity(0.04)` background, cornerRadius 4, saves on submit
- Run button (setup only): `play.fill` icon (`.system(size: 9)`), disabled when command is empty
- Command output (setup only): `.system(size: 9, design: .monospaced)`, `.secondary`, 6 line limit, `.primary.opacity(0.03)` background

**Shell Section** (`shellSection`)
- Section header: "Shell"
- Picker: menu style, `.system(size: 10)`, options from `shellOptions`
- Saves on change via `.onChange`

**Working Directory Section** (`workingDirectorySection`)
- Section header: "Working Directory"
- Text field: `TextField("Subdirectory (optional)")`, same styling as command fields
- Saves on submit

**Info Section** (`infoSection`)
- Path: `workspace.worktreePath` (`.system(size: 9, design: .monospaced)`, `.tertiary`, single line, middle truncation)
- Branch: `workspace.branch` (`.system(size: 9, design: .monospaced)`, `.tertiary`)

**Run Confirmation Alert**
- Title: "Run setup command?"
- Message: displays the setup command text
- Buttons: "Run" and "Cancel"

### ProfileEditorSheet State Properties

| Property | Type | Purpose |
|----------|------|---------|
| `profile` | `EnvironmentProfile` | Original profile being edited (let) |
| `onSave` | `(EnvironmentProfile) -> Void` | Save callback |
| `onCancel` | `() -> Void` | Cancel callback |
| `name` | `@State String` | Editable profile name |
| `colorName` | `@State String` | Editable color selection |
| `vars` | `@State [(key: String, value: String)]` | Editable key-value pairs |
| `newKey` | `@State String` | New variable key input |
| `newValue` | `@State String` | New variable value input |

### ProfileEditorSheet UI Elements

**Header**
- Colored dot (8x8), name field (`.system(size: 13, weight: .semibold)`, `.plain`), var count (`.system(size: 10)`, `.tertiary`)
- Padding: 12

**Color Picker**
- 8 circles (16x16): green, orange, red, blue, purple, teal, indigo, pink
- Selected: white 2pt stroke border + colored shadow (`.opacity(0.4)`, radius 2)
- Padding: horizontal 12, bottom 8

**Variable List**
- Each row: KEY field (`.system(size: 11, weight: .medium, design: .monospaced)`, width 120), "=" separator, value field (`.system(size: 11, design: .monospaced)`), delete button (`xmark.circle`, `.system(size: 10)`)
- Row padding: horizontal 12, vertical 5
- Dividers between rows: `.opacity(0.15)`

**Add Variable Row**
- Same layout as variable row but with `plus.circle.fill` button (`.system(size: 12)`, `.accentColor`)
- Submits on enter key
- Disabled when key is empty/whitespace
- Background: `.primary.opacity(0.02)`

**Quick Add Menu**
- Label: "Quick Add" with `plus.circle` icon (`.system(size: 10)`)
- Borderless button style, frame width 90
- 10 preset variables:

| Key | Default Value |
|-----|---------------|
| NODE_ENV | development |
| DEBUG | * |
| LOG_LEVEL | debug |
| PORT | 3000 |
| DATABASE_URL | postgres://localhost:5432/mydb |
| RUST_LOG | debug |
| FLASK_ENV | development |
| RAILS_ENV | development |
| API_URL | http://localhost:8080 |
| AWS_REGION | us-east-1 |

**Footer**
- Cancel button: `.plain`, `.secondary`
- Save button: `.borderedProminent`, `.controlSize(.small)`, disabled when name is empty
- Padding: 12

**Sheet Dimensions**: 400 x 360

### Methods

**WorkspaceSettingsPopover**

| Method | Purpose |
|--------|---------|
| `loadSettings()` | Loads `WorkspaceConfig` from `{repoPath}/.ghostset/config.json`, populates state |
| `saveCommands()` | Saves setup/teardown commands to repo config |
| `saveShell()` | Saves shell selection to repo config (nil if "Default") |
| `saveWorkingDirectory()` | Saves working directory to repo config (nil if empty) |
| `loadRepoConfig()` | Reads and decodes `WorkspaceConfig` from disk |
| `saveRepoConfig(_:)` | Encodes and writes `WorkspaceConfig` to disk, creates `.ghostset` dir if needed |
| `runSetupCommand()` | Executes setup command via `/bin/sh -c` in workspace's worktree directory on background thread, captures stdout+stderr, updates `commandOutput` on main thread |
| `sectionHeader(_:)` | Helper returning uppercase section header text view |

**ProfileEditorSheet**

| Method | Purpose |
|--------|---------|
| `addVar()` | Trims and uppercases the new key, appends to `vars`, clears inputs |
| `addIfMissing(_:_:)` | Adds a quick-add variable only if the key doesn't already exist |
| `varBinding(_:_:)` | Creates a `Binding<String>` for a specific variable at a given index using a key path |

### Persistence

Settings are stored in two locations:
1. **Per-repo config**: `{workspace.repoPath}/.ghostset/config.json` -- stores setup/teardown commands, shell, working directory
2. **Global profiles**: Managed by `WorktreeManager` which delegates to `WorkspacePersistence` storing in `~/.ghostset/state.json`

## Design Consistency

| Element | Font | Color | Spacing |
|---------|------|-------|---------|
| View title | `.system(size: 12, weight: .semibold)` | Primary | -- |
| Section headers | `.system(size: 9, weight: .medium)` | `.tertiary` | uppercase |
| Profile pill name | `.system(size: 10)` | Primary/secondary | horizontal 8, vertical 4 |
| Profile var count | `.system(size: 8)` | `.tertiary` | -- |
| Active badge | `.system(size: 8, weight: .medium)` | Profile color | horizontal 4, vertical 1 |
| Variable key | `.system(size: 9, weight: .medium, design: .monospaced)` | `.secondary` | -- |
| Variable value | `.system(size: 9, design: .monospaced)` | `.tertiary` | -- |
| Command field | `.system(size: 10, design: .monospaced)` | Primary | padding 6 |
| Info text | `.system(size: 9, design: .monospaced)` | `.tertiary` | -- |
| Popover frame | -- | `windowBackgroundColor` | 320 x 480 |
| Editor sheet | -- | `windowBackgroundColor` | 400 x 360 |
| Pill active bg | -- | Profile color `.opacity(0.15)` | cornerRadius 5 |
| Pill inactive bg | -- | `.primary.opacity(0.04)` | cornerRadius 5 |

## Ghostty Codebase Alignment

### Types Used
- `WorktreeManager` (environmentProfiles, activeProfileID, activeProfile, upsertEnvironmentProfile, removeEnvironmentProfile, setActiveProfile)
- `Workspace` (worktreePath, repoPath, branch)
- `EnvironmentProfile` (id, name, variables, colorName, presets)
- `WorkspaceConfig` (setupCommand, teardownCommand, shell, workingDirectory)
- `AgentType` (referenced via WorkspaceConfig.defaultAgent)
- `TagDefinition` (swiftUIColor(for:))
- `FlowLayout` (custom SwiftUI layout)

### Integration Points
- Presented as a popover from the workspace sidebar context menu or settings button
- Loads settings on appear via `.onAppear { loadSettings() }`
- Profile editing opens as a `.sheet(item:)` with `ProfileEditorSheet`
- Run confirmation uses SwiftUI `.alert(isPresented:)`
- Shell command execution uses `Process` with `/bin/sh -c` on `DispatchQueue.global(qos: .userInitiated)`

## Known Issues

1. **Setup command runs on background thread with DispatchQueue, not async/await**: Uses `DispatchQueue.global` for process execution instead of modern structured concurrency.
2. **No teardown command execution**: Only setup commands have a run button; teardown commands can only be configured, not executed from the UI.
3. **No command output scrolling**: Output is limited to 6 lines with no scroll or expansion.
4. **Shell path not validated**: The selected shell path is saved without checking if the binary exists.
5. **Working directory not validated**: Subdirectory path is saved without verifying it exists within the worktree.
6. **Per-repo config stored in repo directory**: `.ghostset/config.json` is created inside the repository, which may be committed accidentally if `.gitignore` is not updated.
7. **Profile color picker offers different colors in popover vs editor**: New profile form has 6 colors (green, orange, red, blue, purple, teal); editor sheet has 8 (adds indigo, pink).
8. **Variable keys are uppercased on add**: `addVar()` uppercases the key, but existing variables from profiles are not normalized, leading to potential case mismatches.
9. **No process timeout**: `runSetupCommand()` calls `process.waitUntilExit()` with no timeout, potentially blocking the background thread indefinitely.

## Future Enhancements

- Add async/await for command execution with cancellation support
- Add teardown command execution button
- Add process timeout and kill button for long-running commands
- Add command history per workspace
- Validate shell path and working directory on save
- Add `.ghostset` to auto-generated `.gitignore`
- Unify color options between new profile form and editor
- Add environment variable validation (warn on common mistakes)
- Support importing `.env` files directly
- Add profile comparison view

## Changelog

- 2026-03-20: Initial spec
