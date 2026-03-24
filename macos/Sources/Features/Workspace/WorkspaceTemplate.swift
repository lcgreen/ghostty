import Foundation

/// A variable that can be substituted into template commands and paths.
struct TemplateVariable: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String         // e.g. "port"
    var defaultValue: String // e.g. "3000"
    var description: String  // e.g. "Dev server port"
    var required: Bool

    init(name: String = "", defaultValue: String = "", description: String = "", required: Bool = false) {
        self.id = UUID()
        self.name = name
        self.defaultValue = defaultValue
        self.description = description
        self.required = required
    }
}

/// A tab layout definition within a template.
struct TemplateTab: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var agent: AgentType?
    var command: String?       // Command to auto-run on creation
    var autoRun: Bool          // If true, press Enter automatically; if false, just pre-fill
    var isPinned: Bool
    var colorName: String?
    var iconOverride: String?
    var splits: [TemplateSplit]    // Flat splits (simple cases)
    var layout: TemplatePane?      // Recursive layout (complex nested splits)

    init(
        title: String = "Shell",
        agent: AgentType? = nil,
        command: String? = nil,
        autoRun: Bool = false,
        isPinned: Bool = false,
        colorName: String? = nil,
        iconOverride: String? = nil,
        splits: [TemplateSplit] = [],
        layout: TemplatePane? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.agent = agent
        self.command = command
        self.autoRun = autoRun
        self.isPinned = isPinned
        self.colorName = colorName
        self.iconOverride = iconOverride
        self.splits = splits
        self.layout = layout
    }

}

/// A pane definition — can be a leaf (single terminal) or a split (two panes).
/// Recursive structure allows nested splits.
indirect enum TemplatePane: Codable, Identifiable, Hashable {
    case terminal(TemplatePaneLeaf)
    case split(TemplatePaneSplit)

    var id: UUID {
        switch self {
        case .terminal(let leaf): return leaf.id
        case .split(let split): return split.id
        }
    }

}

/// A single terminal pane within a template.
struct TemplatePaneLeaf: Codable, Identifiable, Hashable {
    let id: UUID
    var command: String?
    var autoRun: Bool
    var subdirectory: String?

    init(command: String? = nil, autoRun: Bool = false, subdirectory: String? = nil) {
        self.id = UUID()
        self.command = command
        self.autoRun = autoRun
        self.subdirectory = subdirectory
    }
}

/// A split containing two panes with a direction.
struct TemplatePaneSplit: Codable, Identifiable, Hashable {
    let id: UUID
    var direction: SplitDirection
    var first: TemplatePane
    var second: TemplatePane

    init(direction: SplitDirection = .horizontal, first: TemplatePane, second: TemplatePane) {
        self.id = UUID()
        self.direction = direction
        self.first = first
        self.second = second
    }
}

/// Flat split definition for backward compatibility and simple cases.
struct TemplateSplit: Codable, Identifiable, Hashable {
    let id: UUID
    var command: String?
    var autoRun: Bool
    var subdirectory: String?
    var direction: SplitDirection

    init(
        command: String? = nil,
        autoRun: Bool = false,
        subdirectory: String? = nil,
        direction: SplitDirection = .horizontal
    ) {
        self.id = UUID()
        self.command = command
        self.autoRun = autoRun
        self.subdirectory = subdirectory
        self.direction = direction
    }

}

/// A reusable workspace template — full workspace snapshot including tabs, splits, and commands.
struct WorkspaceTemplate: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var repoPath: String?
    var baseBranch: String
    var agent: AgentType?
    var tags: [String]
    var taskDescription: String?
    var environmentVariables: [String: String]
    var setupCommand: String?
    var onCreateCommand: String?   // Multi-line script to run in worktree after workspace is created
    var onDestroyCommand: String?  // Multi-line script to run in worktree before workspace is destroyed
    var category: TemplateCategory
    var tabs: [TemplateTab]    // Full tab layout with splits and commands
    var variables: [TemplateVariable]   // Substitution variables for commands/paths
    let createdAt: Date

    init(
        name: String,
        repoPath: String? = nil,
        baseBranch: String = "main",
        agent: AgentType? = nil,
        tags: [String] = [],
        taskDescription: String? = nil,
        environmentVariables: [String: String] = [:],
        setupCommand: String? = nil,
        onCreateCommand: String? = nil,
        onDestroyCommand: String? = nil,
        category: TemplateCategory = .aiAgents,
        tabs: [TemplateTab] = [],
        variables: [TemplateVariable] = []
    ) {
        self.id = UUID()
        self.name = name
        self.repoPath = repoPath
        self.baseBranch = baseBranch
        self.agent = agent
        self.tags = tags
        self.taskDescription = taskDescription
        self.environmentVariables = environmentVariables
        self.setupCommand = setupCommand
        self.onCreateCommand = onCreateCommand
        self.onDestroyCommand = onDestroyCommand
        self.category = category
        self.tabs = tabs
        self.variables = variables
        self.createdAt = Date()
    }

    // Backward-compatible decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        repoPath = try container.decodeIfPresent(String.self, forKey: .repoPath)
        baseBranch = try container.decodeIfPresent(String.self, forKey: .baseBranch) ?? "main"
        agent = try container.decodeIfPresent(AgentType.self, forKey: .agent)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        taskDescription = try container.decodeIfPresent(String.self, forKey: .taskDescription)
        environmentVariables = try container.decodeIfPresent([String: String].self, forKey: .environmentVariables) ?? [:]
        setupCommand = try container.decodeIfPresent(String.self, forKey: .setupCommand)
        onCreateCommand = try container.decodeIfPresent(String.self, forKey: .onCreateCommand)
        onDestroyCommand = try container.decodeIfPresent(String.self, forKey: .onDestroyCommand)
        category = try container.decodeIfPresent(TemplateCategory.self, forKey: .category) ?? .aiAgents
        tabs = try container.decodeIfPresent([TemplateTab].self, forKey: .tabs) ?? []
        variables = try container.decodeIfPresent([TemplateVariable].self, forKey: .variables) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    /// Returns a cleaned-up copy of the template with invalid data fixed.
    func validated() -> WorkspaceTemplate {
        var t = self
        t.tabs = t.tabs.map { tab in
            var tab = tab
            // If tab has an agent, clear layout commands that are just agent titles
            if tab.agent != nil {
                tab.layout = tab.layout.map { Self.cleanPane($0) }
            }
            // Clear redundant flat splits when recursive layout exists
            if tab.layout != nil && !tab.splits.isEmpty {
                tab.splits = []
            }
            // Clean commands that look like terminal titles, not real commands
            if let cmd = tab.command, Self.looksLikeTitle(cmd) {
                tab.command = nil
            }
            return tab
        }
        return t
    }

    /// Check if a string looks like a terminal title rather than a command.
    private static func looksLikeTitle(_ text: String) -> Bool {
        if text.hasPrefix("✳") || text.hasPrefix("✦") || text.hasPrefix("●") { return true }
        if text.unicodeScalars.contains(where: { !$0.isASCII && !CharacterSet.letters.contains($0) }) { return true }
        return false
    }

    /// Clean a pane tree, removing fake commands from agent terminals.
    private static func cleanPane(_ pane: TemplatePane) -> TemplatePane {
        switch pane {
        case .terminal(var leaf):
            if let cmd = leaf.command, looksLikeTitle(cmd) {
                leaf.command = nil
            }
            return .terminal(leaf)
        case .split(var split):
            split.first = cleanPane(split.first)
            split.second = cleanPane(split.second)
            return .split(split)
        }
    }

    /// Create a template from an existing workspace (basic — no tab snapshot).
    static func from(workspace: Workspace) -> WorkspaceTemplate {
        WorkspaceTemplate(
            name: workspace.name,
            repoPath: workspace.repoPath,
            baseBranch: "main",
            agent: workspace.agent,
            tags: workspace.tags,
            taskDescription: workspace.taskDescription
        )
    }

    /// Create a template with full tab/split snapshot from a workspace's current session.
    static func snapshot(workspace: Workspace, tabGroup: WorkspaceTabGroup) -> WorkspaceTemplate {
        let templateTabs = tabGroup.tabs.map { tab -> TemplateTab in
            let layout = Self.capturePane(
                node: tab.viewModel.surfaceTree.root,
                worktreeRoot: workspace.worktreePath
            )

            // Also build flat splits for backward compat
            var flatSplits: [TemplateSplit] = []
            Self.flattenSplits(node: tab.viewModel.surfaceTree.root, worktreeRoot: workspace.worktreePath, splits: &flatSplits, isFirst: true)

            let firstSurface = tab.viewModel.surfaceTree.first(where: { _ in true })
            let mainCommand = Self.extractCommand(from: firstSurface)

            return TemplateTab(
                title: tab.title,
                agent: tab.agent,
                command: tab.agent != nil ? nil : mainCommand,
                autoRun: tab.agent != nil || mainCommand != nil,
                isPinned: tab.isPinned,
                colorName: tab.colorName,
                iconOverride: tab.iconOverride,
                splits: flatSplits,
                layout: layout
            )
        }

        return WorkspaceTemplate(
            name: "\(workspace.name) Layout",
            repoPath: workspace.repoPath,
            baseBranch: "main",
            agent: workspace.agent,
            tags: workspace.tags,
            taskDescription: workspace.taskDescription,
            tabs: templateTabs
        ).validated()
    }

    /// Recursively capture the split tree as a TemplatePane.
    private static func capturePane(
        node: SplitTree<Ghostty.SurfaceView>.Node?,
        worktreeRoot: String
    ) -> TemplatePane? {
        guard let node else { return nil }
        switch node {
        case .leaf(let surface):
            return .terminal(TemplatePaneLeaf(
                command: extractCommand(from: surface),
                autoRun: extractCommand(from: surface) != nil,
                subdirectory: relativeSubdir(pwd: surface.pwd, root: worktreeRoot)
            ))
        case .split(let split):
            let dir: SplitDirection = split.direction == .horizontal ? .horizontal : .vertical
            guard let first = capturePane(node: split.left, worktreeRoot: worktreeRoot),
                  let second = capturePane(node: split.right, worktreeRoot: worktreeRoot) else {
                return nil
            }
            return .split(TemplatePaneSplit(direction: dir, first: first, second: second))
        }
    }

    /// Extract a command from a surface title (nil if it looks like a shell prompt).
    private static func extractCommand(from surface: Ghostty.SurfaceView?) -> String? {
        guard let surface, !surface.title.isEmpty else { return nil }
        let title = surface.title
        // Filter out non-command titles
        if title.contains("@") || title.hasPrefix("/") || title.hasPrefix("~") { return nil }
        // Filter out titles with special unicode characters (agent badges, etc.)
        if title.unicodeScalars.contains(where: { !$0.isASCII && !CharacterSet.letters.contains($0) }) { return nil }
        // Filter out common non-command patterns
        if title.hasPrefix("✳") || title.hasPrefix("✦") || title.hasPrefix("●") { return nil }
        return title
    }

    private static func relativeSubdir(pwd: String?, root: String) -> String? {
        guard let pwd, pwd.hasPrefix(root) else { return nil }
        let rel = String(pwd.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return rel.isEmpty ? nil : rel
    }

    /// Flatten the split tree into a simple list for backward compat.
    private static func flattenSplits(
        node: SplitTree<Ghostty.SurfaceView>.Node?,
        worktreeRoot: String,
        splits: inout [TemplateSplit],
        isFirst: Bool
    ) {
        guard let node else { return }
        switch node {
        case .leaf(let surface):
            if !isFirst {
                splits.append(TemplateSplit(
                    command: extractCommand(from: surface),
                    autoRun: extractCommand(from: surface) != nil,
                    subdirectory: relativeSubdir(pwd: surface.pwd, root: worktreeRoot)
                ))
            }
        case .split(let split):
            let dir: SplitDirection = split.direction == .horizontal ? .horizontal : .vertical
            flattenSplits(node: split.left, worktreeRoot: worktreeRoot, splits: &splits, isFirst: isFirst)
            var rightSplits: [TemplateSplit] = []
            flattenSplits(node: split.right, worktreeRoot: worktreeRoot, splits: &rightSplits, isFirst: false)
            for s in rightSplits {
                splits.append(TemplateSplit(command: s.command, autoRun: s.autoRun, subdirectory: s.subdirectory, direction: dir))
            }
        }
    }

    /// Duplicate this template with a new ID and name suffix.
    func duplicated() -> WorkspaceTemplate {
        WorkspaceTemplate(
            name: "\(name) Copy",
            repoPath: repoPath,
            baseBranch: baseBranch,
            agent: agent,
            tags: tags,
            taskDescription: taskDescription,
            environmentVariables: environmentVariables,
            setupCommand: setupCommand,
            onCreateCommand: onCreateCommand,
            onDestroyCommand: onDestroyCommand,
            category: category,
            tabs: tabs,
            variables: variables
        )
    }

    /// Built-in template presets.
    static let presets: [WorkspaceTemplate] = [
        WorkspaceTemplate(
            name: "Claude Feature",
            baseBranch: "main",
            agent: .claude,
            tags: ["feature"],
            category: .aiAgents
        ),
        WorkspaceTemplate(
            name: "Claude Bugfix",
            baseBranch: "main",
            agent: .claude,
            tags: ["bugfix"],
            category: .aiAgents
        ),
        WorkspaceTemplate(
            name: "Codex Auto",
            baseBranch: "main",
            agent: .codex,
            tags: ["feature"],
            category: .aiAgents
        ),
        WorkspaceTemplate(
            name: "Plain Shell",
            baseBranch: "main",
            category: .manual
        ),
    ]

}

// MARK: - Template Category

enum TemplateCategory: String, Codable, CaseIterable {
    case aiAgents = "AI Agents"
    case manual = "Manual"
    case cicd = "CI/CD"
    case custom = "Custom"

    var iconName: String {
        switch self {
        case .aiAgents: return "cpu"
        case .manual: return "terminal"
        case .cicd: return "gearshape.2"
        case .custom: return "star"
        }
    }
}

/// Persistence for workspace templates.
final class TemplatePersistence {
    private let path: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ghostset/templates.json"
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func load() -> [WorkspaceTemplate] {
        guard let data = FileManager.default.contents(atPath: path) else {
            return WorkspaceTemplate.presets
        }
        do {
            return try decoder.decode([WorkspaceTemplate].self, from: data)
        } catch {
            print("[TemplatePersistence] Warning: failed to decode templates.json — returning empty array to avoid overwriting user data. Error: \(error)")
            return []
        }
    }

    func save(_ templates: [WorkspaceTemplate]) {
        do {
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let data = try encoder.encode(templates)
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            print("[TemplatePersistence] Failed to save: \(error)")
        }
    }
}
