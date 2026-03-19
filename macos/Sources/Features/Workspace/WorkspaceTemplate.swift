import Foundation

/// A reusable workspace template — save and recall configurations.
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
    var category: TemplateCategory
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
        category: TemplateCategory = .aiAgents
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
        self.category = category
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
        category = try container.decodeIfPresent(TemplateCategory.self, forKey: .category) ?? .aiAgents
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    /// Create a template from an existing workspace.
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
            category: category
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

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: WorkspaceTemplate, rhs: WorkspaceTemplate) -> Bool {
        lhs.id == rhs.id
    }
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
            return WorkspaceTemplate.presets
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
