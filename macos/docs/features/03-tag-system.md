# Tag System

## Overview

The tag system provides a categorization and discovery layer for Ghostset workspaces. Each workspace can be labeled with one or more tags (e.g., "feature", "bugfix", "python"), enabling filtering, visual differentiation, and automatic classification. Tags are defined as `TagDefinition` value types, persisted to `~/.ghostset/state.json`, and rendered throughout the sidebar, workspace rows, settings popovers, and the new-workspace sheet. The system ships with five preset tags, ten palette colors, an auto-tagging engine driven by keyword matching, and a language-detection scanner that inspects repository root files.

## Architecture

### Key Files

| File | Role |
|------|------|
| `Sources/Features/Workspace/TagDefinition.swift` | Core model: `TagDefinition` struct, preset tags, color palette, auto-tag keywords, language detection, utility methods |
| `Sources/Features/Workspace/WorkspaceModel.swift` | `Workspace` struct holds `tags: [String]` — an array of tag name strings associated with each workspace |
| `Sources/Features/Workspace/WorktreeManager.swift` | Owns `@Published var tagDefinitions: [TagDefinition]`, loads from persistence on init, exposes `tagDefinition(for:)`, `upsertTagDefinition(_:)`, `removeTagDefinition(_:)` |
| `Sources/Features/Workspace/WorkspacePersistence.swift` | Reads/writes `tagDefinitions` array inside `~/.ghostset/state.json`; falls back to `TagDefinition.presets` when file is missing or empty |
| `Sources/Features/Workspace/WorkspaceSidebar.swift` | Renders tag filter chips, tag management UI, color swatch picker, usage counts, and creation of new custom tags |
| `Sources/Features/Workspace/WorkspaceRow.swift` | Accepts `tagLookup: (String) -> TagDefinition` closure to resolve tag names to colored badges |
| `Sources/Features/Workspace/NewWorkspaceSheet.swift` | Calls `TagDefinition.inferTags(from:)` on workspace name changes to auto-select tags; renders tag toggle buttons |
| `Sources/Features/Workspace/WorkspaceSettingsPopover.swift` | Uses `TagDefinition.swiftUIColor(for:)` for profile color rendering and color swatch selection |
| `Sources/Features/Workspace/EnvironmentManagerView.swift` | Uses `TagDefinition.swiftUIColor(for:)` for environment profile color indicators |

### Data Models

#### `TagDefinition` (struct, Codable, Identifiable, Hashable)

| Property | Type | Description |
|----------|------|-------------|
| `name` | `String` (let) | Immutable identifier, used as the Identifiable `id` |
| `colorName` | `String` (var) | Key into the color palette (e.g., `"blue"`, `"teal"`) |
| `iconName` | `String?` (var) | Optional SF Symbol name for visual display |
| `parentTag` | `String?` (var) | Optional parent for hierarchical tags |

**Computed properties:**

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Returns `name` |
| `color` | `Color` | Calls `Self.swiftUIColor(for: colorName)` |
| `displayName` | `String` | If `parentTag` is set, returns `"\(parent)/\(name)"`; otherwise returns `name` |

**Initializers:**

1. `init(name:colorName:iconName:parentTag:)` — standard memberwise initializer with `iconName` and `parentTag` defaulting to `nil`.
2. `init(from decoder: Decoder)` — backward-compatible Codable initializer that decodes `iconName` and `parentTag` as optional (using `decodeIfPresent`), allowing state files created before these fields existed to load without error.

#### `Workspace.tags` (on `Workspace` struct)

- Type: `[String]`
- Default: `[]` (empty array)
- Decoded with `decodeIfPresent` fallback to `[]` for backward compatibility.
- Stores tag names (not full `TagDefinition` objects), resolved at display time via `WorktreeManager.tagDefinition(for:)`.

### Feature Connections

- **WorktreeManager** is the runtime owner of `tagDefinitions`. It loads them from `WorkspacePersistence` during `init` and provides lookup/upsert/remove methods.
- **WorkspacePersistence** serializes `tagDefinitions` as part of a `PersistenceState` struct that also contains workspaces and other state. When `tagDefinitions` is `nil` or empty on load, it falls back to `TagDefinition.presets`.
- **NewWorkspaceSheet** auto-selects tags by calling `TagDefinition.inferTags(from:)` whenever the workspace name text field changes.
- **WorkspaceSidebar** allows users to create custom tags via a popover with a name field and color swatch picker that iterates `TagDefinition.availableColors`. It displays usage counts via `TagDefinition.usageCount(for:in:)`.
- **WorkspaceRow** receives a `tagLookup` closure (typically `manager.tagDefinition(for:)`) to resolve each tag name string into a colored `TagDefinition` for badge rendering.

## Current Implementation

### Preset Tags

Five built-in tags ship with every new installation:

| Name | Color | Icon (SF Symbol) | Purpose |
|------|-------|-------------------|---------|
| `feature` | `blue` | `star` | New feature development |
| `bugfix` | `red` | `ladybug` | Bug fixes, hotfixes, patches |
| `refactor` | `purple` | `arrow.triangle.2.circlepath` | Code restructuring and cleanup |
| `experiment` | `orange` | `flask` | Spikes, prototypes, exploratory work |
| `review` | `teal` | `eye` | Code review, PR review |

### Available Colors (Palette)

Ten colors are available for tag assignment. Each maps to a SwiftUI `Color` value:

| Index | Key | Display Label | SwiftUI Color |
|-------|-----|---------------|---------------|
| 0 | `"blue"` | Blue | `.blue` |
| 1 | `"indigo"` | Indigo | `.indigo` |
| 2 | `"purple"` | Purple | `.purple` |
| 3 | `"pink"` | Pink | `.pink` |
| 4 | `"red"` | Red | `.red` |
| 5 | `"orange"` | Orange | `.orange` |
| 6 | `"yellow"` | Yellow | `.yellow` |
| 7 | `"green"` | Green | `.green` |
| 8 | `"teal"` | Teal | `.teal` |
| 9 | `"mint"` | Mint | `.mint` |

**Fallback behavior:** Any unrecognized `colorName` resolves to `.secondary` via the `default` case in `swiftUIColor(for:)`.

### Color Resolution Method

`static func swiftUIColor(for name: String) -> Color`

A switch statement maps each of the 10 color keys to their SwiftUI counterpart. The `default` case returns `.secondary`. This method is used across multiple views: `WorkspaceSettingsPopover`, `EnvironmentManagerView`, `WorkspaceSidebar`, and internally by the `color` computed property.

### Auto-Tag Keywords

The `autoTagKeywords` dictionary maps 18 keywords to 5 tag categories:

#### Bugfix Keywords (4 keywords)

| Keyword | Resolves To |
|---------|-------------|
| `"fix"` | `"bugfix"` |
| `"bug"` | `"bugfix"` |
| `"hotfix"` | `"bugfix"` |
| `"patch"` | `"bugfix"` |

#### Feature Keywords (4 keywords)

| Keyword | Resolves To |
|---------|-------------|
| `"feat"` | `"feature"` |
| `"feature"` | `"feature"` |
| `"add"` | `"feature"` |
| `"implement"` | `"feature"` |

#### Refactor Keywords (4 keywords)

| Keyword | Resolves To |
|---------|-------------|
| `"refactor"` | `"refactor"` |
| `"cleanup"` | `"refactor"` |
| `"clean"` | `"refactor"` |
| `"reorganize"` | `"refactor"` |

#### Experiment Keywords (4 keywords)

| Keyword | Resolves To |
|---------|-------------|
| `"experiment"` | `"experiment"` |
| `"spike"` | `"experiment"` |
| `"try"` | `"experiment"` |
| `"proto"` | `"experiment"` |

#### Review Keywords (2 keywords)

| Keyword | Resolves To |
|---------|-------------|
| `"review"` | `"review"` |
| `"pr"` | `"review"` |

### Tag Inference Method

`static func inferTags(from text: String) -> [String]`

**Algorithm:**

1. Lowercases the input text.
2. Splits on non-alphanumeric characters (`CharacterSet.alphanumerics.inverted`).
3. Filters out empty strings.
4. For each word, looks up `autoTagKeywords[word]`.
5. Collects matches into a `Set<String>` (deduplicating tag names).
6. Returns the set as a sorted `[String]` array.

**Behavior notes:**
- Matching is exact, case-insensitive (due to lowercasing), and word-boundary-aware (due to splitting on non-alphanumeric characters).
- A workspace named `"fix-auth-bug"` would match both `"fix"` and `"bug"`, but both resolve to `"bugfix"`, so the result is `["bugfix"]`.
- A workspace named `"feat/add-login"` would match `"feat"` and `"add"`, both resolving to `"feature"`, yielding `["feature"]`.
- A workspace named `"refactor-and-fix-tests"` would yield `["bugfix", "refactor"]` (sorted alphabetically).

### Language Detection Method

`static func detectLanguageTags(repoPath: String) -> [String]`

Scans the top-level directory of a repository path for sentinel files and returns language tag names:

| Sentinel File(s) | Language Tag | Notes |
|-------------------|-------------|-------|
| `package.json` OR `tsconfig.json` | `"javascript"` | Covers both JS and TS projects |
| `requirements.txt` OR `pyproject.toml` OR `setup.py` | `"python"` | Covers pip, poetry/flit, and setuptools |
| `go.mod` | `"go"` | Go modules |
| `Cargo.toml` | `"rust"` | Cargo/Rust projects |
| `build.zig` | `"zig"` | Zig build system |
| `Package.swift` | `"swift"` | Swift Package Manager |

**Algorithm:**

1. Uses `FileManager.default.contentsOfDirectory(atPath:)` to list the repo root.
2. Converts the file list to a `Set<String>` for O(1) lookups.
3. Checks for each sentinel file in order; appends the language tag if found.
4. Returns the accumulated array (order is deterministic: javascript, python, go, rust, zig, swift).
5. Returns an empty array if the directory cannot be read (silently catches errors with `try?`).

**Limitations:**
- Only scans the top-level directory (not recursive).
- Does not detect TypeScript as a separate tag (subsumes under `"javascript"`).
- Does not detect languages without standard root-level config files (e.g., C, C++, Java with Gradle).
- Language tags are plain strings, not linked to `TagDefinition` presets (no preset color/icon assigned).

### Usage Count Method

`static func usageCount(for tagName: String, in workspaces: [Workspace]) -> Int`

Filters the workspace array by `$0.tags.contains(tagName)` and returns the count. Used in the sidebar to display how many workspaces use each tag.

### Next Unused Color Method

`static func nextUnusedColor(usedColors: Set<String>) -> String`

Iterates `availableColors` in palette order and returns the first color whose `name` is not in `usedColors`. If all 10 colors are in use, wraps around to the first color (`"blue"`). This ensures new custom tags get visually distinct colors when possible.

## Design Consistency

### Colors

- The 10-color palette is drawn entirely from SwiftUI's built-in named colors, ensuring consistency with the macOS system appearance and automatic dark-mode adaptation.
- The fallback color `.secondary` (used for unknown `colorName` values) is a system-adaptive gray that works in both light and dark modes.
- The same `swiftUIColor(for:)` method is used consistently across all views (`WorkspaceSettingsPopover`, `EnvironmentManagerView`, `WorkspaceSidebar`, `WorkspaceRow`), preventing color drift.
- Preset tags use 5 of the 10 available colors (blue, red, purple, orange, teal), leaving indigo, pink, yellow, green, and mint available for custom tags.

### Naming Conventions

- Tag names are lowercase, single-word strings (e.g., `"bugfix"`, `"feature"`, `"refactor"`).
- Color keys are lowercase, matching SwiftUI color names exactly (e.g., `"blue"`, not `"Blue"` or `"#0000FF"`).
- Icon names use SF Symbol identifiers directly (e.g., `"star"`, `"ladybug"`, `"flask"`).
- Language detection tags follow the same lowercase convention (e.g., `"javascript"`, `"python"`).
- The `displayName` property supports hierarchical naming with `/` as the separator (e.g., `"frontend/react"`), although no presets currently use this feature.

## Ghostty Codebase Alignment

- `TagDefinition` follows the Ghostty macOS codebase patterns: it is a `struct` (value type), `Codable` for JSON serialization, `Identifiable` for SwiftUI lists, and `Hashable` for use in sets.
- The persistence format mirrors the existing `WorkspacePersistence` JSON structure, adding `tagDefinitions` as an optional array in the `PersistenceState` struct with backward-compatible decoding.
- The `WorktreeManager` holds `tagDefinitions` as a `@Published` property, consistent with how it manages `workspaces` and other observable state.
- Auto-tag keywords align with conventional commit prefixes (`feat`, `fix`, `refactor`) commonly used in git-based workflows.
- The file is located under `Sources/Features/Workspace/`, consistent with the feature-based directory organization used throughout the Ghostset layer.

## Known Issues

1. **Language tags are not linked to TagDefinition presets.** `detectLanguageTags` returns plain strings (e.g., `"javascript"`) that have no corresponding `TagDefinition` with a color or icon. When displayed, these fall back to a `TagDefinition(name:, colorName: "secondary")` constructed by `WorktreeManager.tagDefinition(for:)`.

2. **TypeScript is not separately detected.** Both `package.json` and `tsconfig.json` resolve to the same `"javascript"` tag. A project with only `tsconfig.json` (unlikely but possible) would still be tagged `"javascript"`.

3. **No recursive language detection.** Only root-level files are scanned. A monorepo with language-specific subdirectories (e.g., `backend/go.mod`, `frontend/package.json`) would not detect those languages.

4. **Auto-tag keyword `"try"` is overly broad.** The word "try" appears frequently in natural language workspace names (e.g., "try new layout") and may incorrectly auto-tag as `"experiment"`.

5. **Auto-tag keyword `"add"` may be too generic.** Common in non-feature contexts (e.g., "add tests", "add docs") but always resolves to `"feature"`.

6. **No tag deletion cascade.** When a tag definition is removed via `removeTagDefinition`, workspaces that reference that tag name in their `tags` array are not automatically updated. The orphaned tag name strings persist until manually removed.

7. **Hierarchical tags (parentTag) are defined but not exercised.** The `parentTag` property and `displayName` computed property support tag hierarchies, but no presets or UI flows create hierarchical tags.

8. **Color exhaustion wraps silently.** `nextUnusedColor` returns `"blue"` when all 10 colors are in use, which may create visual ambiguity with the existing `"feature"` preset tag.

9. **`inferTags` does not detect partial matches.** The keyword `"proto"` matches only the exact word "proto", not "prototype" or "prototyping", since the input is split on non-alphanumeric characters.

## Future Enhancements

1. **Language tag presets.** Add `TagDefinition` presets for detected languages with appropriate colors and icons (e.g., `"python"` with yellow and a snake icon).

2. **Smart auto-tagging.** Expand beyond exact keyword matching to support substring/prefix matching, regex patterns, or ML-based classification.

3. **Tag groups and hierarchies.** Fully implement the `parentTag` system with UI support for nested tag trees (e.g., `"frontend/react"`, `"frontend/vue"`).

4. **Tag-based workspace filtering.** Add sidebar filter chips that restrict the workspace list to selected tags (partially implemented in sidebar).

5. **Custom icons for tags.** Allow users to pick SF Symbols when creating custom tags, not just colors.

6. **Tag merge and rename.** Support renaming a tag across all workspaces, and merging two tags into one.

7. **Recursive language detection.** Scan subdirectories (with depth limits) to detect languages in monorepos.

8. **Tag statistics dashboard.** Show tag usage distribution, most active tags, and tag-based workspace grouping.

9. **Tag-aware workspace templates.** Pre-configure workspace settings (agent type, environment variables) based on assigned tags.

10. **Import/export tag definitions.** Allow sharing tag configurations across machines or teams.

## Changelog

- 2026-03-20: Initial spec. Documented all properties, methods, preset tags, color palette, auto-tag keywords, language detection rules, and known issues from `TagDefinition.swift` at commit `8aefb7f`.
