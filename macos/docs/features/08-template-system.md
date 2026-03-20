# Template System

## Overview

The template system provides reusable workspace configurations that can be saved, edited, duplicated, imported, and exported. A `WorkspaceTemplate` captures agent type, base branch, tags, environment variables, setup commands, and category. The `TemplateManagerView` offers a full CRUD interface organized by category, while `TemplatePersistence` handles JSON serialization to `~/.ghostset/templates.json`. Four built-in preset templates are provided out of the box.

## Architecture

### Key Files

| File | Role |
|------|------|
| `Sources/Features/Workspace/WorkspaceTemplate.swift` | `WorkspaceTemplate` model, `TemplateCategory` enum, `TemplatePersistence` class |
| `Sources/Features/Workspace/TemplateManagerView.swift` | SwiftUI sheet for template CRUD management |

### Data Models

**WorkspaceTemplate** (struct, Codable, Identifiable, Hashable)
- `id: UUID` -- unique identifier, generated on creation
- `name: String` -- template display name
- `repoPath: String?` -- optional default repository path
- `baseBranch: String` -- branch to create worktrees from (default: `"main"`)
- `agent: AgentType?` -- optional agent to auto-launch
- `tags: [String]` -- tag labels to apply to created workspaces
- `taskDescription: String?` -- optional task description
- `environmentVariables: [String: String]` -- custom environment variables (default: `[:]`)
- `setupCommand: String?` -- optional shell command to run after workspace creation
- `category: TemplateCategory` -- organizational category (default: `.aiAgents`)
- `createdAt: Date` -- creation timestamp

**TemplateCategory** (enum, String, Codable, CaseIterable)
| Case | Raw Value | Icon |
|------|-----------|------|
| `.aiAgents` | `"AI Agents"` | `"cpu"` |
| `.manual` | `"Manual"` | `"terminal"` |
| `.cicd` | `"CI/CD"` | `"gearshape.2"` |
| `.custom` | `"Custom"` | `"star"` |

**TemplatePersistence** (final class)
- `path: String` -- `~/.ghostset/templates.json`
- `encoder: JSONEncoder` -- pretty-printed, sorted keys, ISO 8601 dates
- `decoder: JSONDecoder` -- ISO 8601 dates

### Feature Connections

- **WorktreeManager** -- manages template list via `manager.templates`, `manager.saveTemplate()`, `manager.removeTemplate()`, `manager.replaceAllTemplates()`, `manager.tagDefinitions`
- **Workspace** -- `WorkspaceTemplate.from(workspace:)` creates a template from an existing workspace
- **AgentType** -- provides agent options for template configuration
- **TagDefinition** -- provides tag options and colors for template configuration

## Current Implementation

### WorkspaceTemplate Methods

| Method | Signature | Purpose |
|--------|-----------|---------|
| `init(name:repoPath:baseBranch:agent:tags:taskDescription:environmentVariables:setupCommand:category:)` | Standard initializer | Creates new template with generated UUID and current timestamp |
| `init(from decoder: Decoder)` | Codable initializer | Backward-compatible decoding with defaults for missing fields |
| `from(workspace:)` | `static func from(workspace: Workspace) -> WorkspaceTemplate` | Creates template from existing workspace, copies name, repoPath, agent, tags, taskDescription |
| `duplicated()` | `func duplicated() -> WorkspaceTemplate` | Creates copy with new UUID and " Copy" name suffix |
| `hash(into:)` | Hashable | Hashes by `id` only |
| `==` | Equatable | Compares by `id` only |

### Built-in Presets

| Name | Agent | Tags | Category |
|------|-------|------|----------|
| "Claude Feature" | `.claude` | `["feature"]` | `.aiAgents` |
| "Claude Bugfix" | `.claude` | `["bugfix"]` | `.aiAgents` |
| "Codex Auto" | `.codex` | `["feature"]` | `.aiAgents` |
| "Plain Shell" | none | `[]` | `.manual` |

### TemplatePersistence Methods

| Method | Signature | Purpose |
|--------|-----------|---------|
| `load()` | `func load() -> [WorkspaceTemplate]` | Loads from `~/.ghostset/templates.json`, returns presets on failure or missing file |
| `save(_:)` | `func save(_ templates: [WorkspaceTemplate])` | Encodes and writes to disk, creates directory if needed |

### TemplateManagerView State Properties

| Property | Type | Purpose |
|----------|------|---------|
| `manager` | `@ObservedObject WorktreeManager` | Source of templates and tag definitions |
| `editingTemplate` | `@State WorkspaceTemplate?` | Template currently being edited (nil = none) |
| `showingNew` | `@State Bool` | Whether the new template form is visible |
| `formName` | `@State String` | Name field in create/edit form |
| `formAgent` | `@State AgentType?` | Agent selection in form (default: `.claude`) |
| `formBranch` | `@State String` | Base branch field in form (default: `"main"`) |
| `formTags` | `@State Set<String>` | Selected tags in form |
| `formCategory` | `@State TemplateCategory` | Category selection in form (default: `.aiAgents`) |

### TemplateManagerView UI Elements

**Header** (`header`)
- Title: "Templates" -- `.system(size: 14, weight: .semibold)`
- Add button: `plus` icon (`.system(size: 11)`), toggles `showingNew`
- Padding: 16

**Template List** (`templateList`)
- Empty state (`emptyState`): `doc.on.doc` icon (`.title2`, `.tertiary`), "No custom templates" heading (`.system(size: 12)`, `.secondary`), description text (`.system(size: 10)`, `.tertiary`), "Create Template" button (`.borderedProminent`, `.controlSize(.small)`)
- Populated state: `ScrollView` with `VStack(spacing: 0)`, sections by `TemplateCategory.allCases`
- New template form appears at bottom of list when `showingNew` is true

**Category Section** (`categorySection(_:items:)`)
- Header: category icon (`.system(size: 9)`) + category name (`.system(size: 10, weight: .semibold)`), `.secondary`, padding horizontal 16, top 10, bottom 4
- Items: `ForEach` with `templateRow` or `templateForm` if editing
- Supports `.onMove` for reordering within category

**Template Row** (`templateRow(_:)`)
- Agent icon: `.system(size: 11)`, agent-colored or `"terminal"` in `.secondary`, frame width 16
- Name: `.system(size: 12, weight: .medium)`
- Agent name: `.system(size: 9)`, `.secondary`
- Branch: `.system(size: 9, design: .monospaced)`, `.tertiary`
- Tag pills: `.system(size: 8, weight: .medium)`, colored with `.opacity(0.8)`, background `.opacity(0.12)`, capsule shape, padding horizontal 4, vertical 1
- Duplicate button: `doc.on.doc` icon (`.system(size: 10)`)
- Delete button: `trash` icon (`.system(size: 10)`)
- Padding: horizontal 16, vertical 8
- Tap gesture begins editing

**Template Form** (`templateForm(editing:)`)
- Title: "Edit Template" or "New Template" (`.system(size: 11, weight: .semibold)`, `.secondary`)
- Name field: `TextField("Template name")` with `.roundedBorder`, `.system(size: 12)`
- Agent menu (`agentMenu`): lists `AgentType.builtIn` + "None" option, borderless button style
- Branch field: `TextField("base branch")` with `.roundedBorder`, `.system(size: 10, design: .monospaced)`, frame width 100
- Category menu (`categoryMenu`): lists `TemplateCategory.allCases`, borderless button style
- Tag toggles (`tagToggles`): horizontal row of `manager.tagDefinitions`, capsule toggle buttons (`.system(size: 9)`), colored when selected with `.opacity(0.15)` background
- Cancel button: `.plain` style, `.secondary`, `.system(size: 11)`
- Save button: `.borderedProminent`, `.controlSize(.small)`, disabled when name is empty
- Background: `Color.accentColor.opacity(0.03)`
- Padding: 16

**Menu Label** (`menuLabel(icon:text:)`)
- Icon: `.system(size: 9)`, text: `.system(size: 10)`, chevron: `.system(size: 7)`
- Background: `Color.secondary.opacity(0.08)`, cornerRadius 4
- Padding: horizontal 8, vertical 4

**Footer** (`footer`)
- Template count: `.system(size: 10)`, `.tertiary`, with pluralization
- "Export All" button: `.plain`, `.secondary`, `.system(size: 11)`
- "Import" button: `.plain`, `.secondary`, `.system(size: 11)`
- "Done" button: `.defaultAction` keyboard shortcut
- Padding: 12

### TemplateManagerView Methods

| Method | Purpose |
|--------|---------|
| `beginEditing(_ template:)` | Sets `editingTemplate` and populates form fields |
| `populateForm(_ template:)` | Fills form state from template properties |
| `saveForm(original:)` | Creates new `WorkspaceTemplate` from form, removes original if editing, saves via manager |
| `cancelForm()` | Resets all form state to defaults, hides new form |
| `moveTemplates(in:from:to:)` | Reorders templates within a category, updates via `manager.replaceAllTemplates()` |
| `exportTemplates()` | Opens `NSSavePanel` (JSON, default name `ghostset-templates.json`), encodes and writes all templates |
| `importTemplates()` | Opens `NSOpenPanel` (JSON, single file), decodes and adds each template via `manager.saveTemplate()` |

### Window Dimensions

| View | Width | Height |
|------|-------|--------|
| TemplateManagerView | 420 | 400 |

## Design Consistency

| Element | Font | Color | Spacing |
|---------|------|-------|---------|
| View title | `.system(size: 14, weight: .semibold)` | Primary | padding 16 |
| Category header | `.system(size: 10, weight: .semibold)` | `.secondary` | horizontal 16, top 10, bottom 4 |
| Template name | `.system(size: 12, weight: .medium)` | Primary | -- |
| Agent name | `.system(size: 9)` | `.secondary` | -- |
| Branch | `.system(size: 9, design: .monospaced)` | `.tertiary` | -- |
| Tag pill | `.system(size: 8, weight: .medium)` | Tag color `.opacity(0.8)` | horizontal 4, vertical 1 |
| Form title | `.system(size: 11, weight: .semibold)` | `.secondary` | -- |
| Form field | `.system(size: 12)` | -- | `.roundedBorder` |
| Footer count | `.system(size: 10)` | `.tertiary` | -- |
| Footer buttons | `.system(size: 11)` | `.secondary` | padding 12 |
| Background | -- | `Color(nsColor: .windowBackgroundColor)` | -- |
| Form bg | -- | `Color.accentColor.opacity(0.03)` | padding 16 |

## Ghostty Codebase Alignment

### Types Used
- `WorktreeManager` (templates, saveTemplate, removeTemplate, replaceAllTemplates, tagDefinitions, tagDefinition(for:))
- `AgentType` (.builtIn, displayName, iconName)
- `AgentColors` (color(for:))
- `TagDefinition` (name, color, swiftUIColor(for:))
- `Workspace` (name, repoPath, agent, tags, taskDescription)

### Integration Points
- `TemplateManagerView` presented as a sheet from the workspace sidebar or via command palette
- `TemplatePersistence` used by `WorktreeManager` to load/save templates on startup and changes
- Templates consumed by `NewWorkspaceSheet` to pre-populate workspace creation forms
- `WorkspaceTemplate.from(workspace:)` enables "Save as Template" from existing workspaces

## Known Issues

1. **Form does not expose all template fields**: `environmentVariables`, `setupCommand`, `taskDescription`, and `repoPath` are not editable in the form -- only name, agent, branch, tags, and category.
2. **Save replaces rather than updates**: `saveForm` removes the old template and creates a new one with a new UUID, breaking any references to the original ID.
3. **Import does not deduplicate**: Importing templates with the same name creates duplicates.
4. **No validation on branch name**: The base branch field accepts any string without verifying it exists.
5. **Export/Import run on main thread**: `NSSavePanel` and `NSOpenPanel` block the main thread during modal presentation.
6. **Backward-compatible decoding defaults category to `.aiAgents`**: Old templates without a category field are always categorized as AI Agents regardless of their actual nature.
7. **Reordering only works within a category**: No way to move a template between categories via drag.

## Future Enhancements

- Add full-field editing in the template form (env vars, setup command, task description, repo path)
- Add template versioning/history
- Add template sharing via URL scheme or clipboard
- Support template inheritance (base template + overrides)
- Add template usage statistics
- Add validation for branch names against available branches
- Support template-level environment profiles
- Add "Apply Template to Existing Workspace" action

## Changelog

- 2026-03-20: Initial spec
