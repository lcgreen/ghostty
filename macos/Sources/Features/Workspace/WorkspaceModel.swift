import Foundation

// MARK: - Workspace

/// A single isolated workspace backed by a git worktree.
/// Each workspace has its own terminal surface and optional agent.
struct Workspace: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let repoPath: String
    let worktreePath: String
    let branch: String
    let createdAt: Date
    var agent: AgentType?
    var status: WorkspaceStatus
    var tags: [String]
    var taskDescription: String?
    var isPinned: Bool
    var isArchived: Bool
    var sortOrder: Int

    init(
        name: String,
        repoPath: String,
        worktreePath: String,
        branch: String,
        agent: AgentType? = nil,
        tags: [String] = [],
        taskDescription: String? = nil,
        isPinned: Bool = false,
        isArchived: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.repoPath = repoPath
        self.worktreePath = worktreePath
        self.branch = branch
        self.createdAt = Date()
        self.agent = agent
        self.status = .creating
        self.tags = tags
        self.taskDescription = taskDescription
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.sortOrder = sortOrder
    }

    // Backward-compatible decoding — old persisted data won't have new fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        repoPath = try container.decode(String.self, forKey: .repoPath)
        worktreePath = try container.decode(String.self, forKey: .worktreePath)
        branch = try container.decode(String.self, forKey: .branch)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        agent = try container.decodeIfPresent(AgentType.self, forKey: .agent)
        status = try container.decode(WorkspaceStatus.self, forKey: .status)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        taskDescription = try container.decodeIfPresent(String.self, forKey: .taskDescription)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    /// Returns a copy with the given name (immutable rename).
    func renamed(to newName: String) -> Workspace {
        var copy = self
        copy.name = newName
        return copy
    }

    /// Returns a copy with pin state toggled.
    func toggledPin() -> Workspace {
        var copy = self
        copy.isPinned = !isPinned
        return copy
    }

    /// Returns a copy with archive state toggled.
    func toggledArchive() -> Workspace {
        var copy = self
        copy.isArchived = !isArchived
        return copy
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Workspace Status

enum WorkspaceStatus: Codable, Equatable {
    case creating
    case ready
    case running(pid: Int32)
    case stopped
    case error(String)

    var isActive: Bool {
        switch self {
        case .running: return true
        default: return false
        }
    }

    var displayLabel: String {
        switch self {
        case .creating: return "Creating..."
        case .ready: return "Ready"
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var iconName: String {
        switch self {
        case .creating: return "circle.dotted"
        case .ready: return "circle"
        case .running: return "circle.fill"
        case .stopped: return "stop.circle"
        case .error: return "exclamationmark.circle"
        }
    }

    var iconColor: String {
        switch self {
        case .creating: return "secondary"
        case .ready: return "blue"
        case .running: return "green"
        case .stopped: return "gray"
        case .error: return "red"
        }
    }
}

// MARK: - Environment Profile

/// A named set of environment variables (e.g., "Development", "Production").
struct EnvironmentProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var variables: [String: String]
    var colorName: String

    init(name: String, variables: [String: String] = [:], colorName: String = "blue") {
        self.id = UUID()
        self.name = name
        self.variables = variables
        self.colorName = colorName
    }

    /// Built-in profile presets for new projects.
    static let presets: [EnvironmentProfile] = [
        EnvironmentProfile(
            name: "Development",
            variables: ["NODE_ENV": "development", "DEBUG": "*", "LOG_LEVEL": "debug"],
            colorName: "green"
        ),
        EnvironmentProfile(
            name: "Staging",
            variables: ["NODE_ENV": "staging", "LOG_LEVEL": "info"],
            colorName: "orange"
        ),
        EnvironmentProfile(
            name: "Production",
            variables: ["NODE_ENV": "production", "LOG_LEVEL": "warn"],
            colorName: "red"
        ),
    ]
}

// MARK: - Workspace Configuration

/// Stored in ~/.ghostset/config.json per-repo
struct WorkspaceConfig: Codable {
    var defaultAgent: AgentType?
    var setupCommand: String?
    var teardownCommand: String?
    var environmentVariables: [String: String]
    var shell: String?
    var workingDirectory: String?
    var environmentProfiles: [EnvironmentProfile]?
    var activeProfileID: UUID?

    init(
        defaultAgent: AgentType? = nil,
        setupCommand: String? = nil,
        teardownCommand: String? = nil,
        environmentVariables: [String: String] = [:],
        shell: String? = nil,
        workingDirectory: String? = nil,
        environmentProfiles: [EnvironmentProfile]? = nil,
        activeProfileID: UUID? = nil
    ) {
        self.defaultAgent = defaultAgent
        self.setupCommand = setupCommand
        self.teardownCommand = teardownCommand
        self.environmentVariables = environmentVariables
        self.shell = shell
        self.workingDirectory = workingDirectory
        self.environmentProfiles = environmentProfiles
        self.activeProfileID = activeProfileID
    }

    /// The currently active profile, if any.
    var activeProfile: EnvironmentProfile? {
        guard let id = activeProfileID else { return nil }
        return environmentProfiles?.first { $0.id == id }
    }

    /// The effective env vars: active profile merged over base vars.
    var effectiveEnvironmentVariables: [String: String] {
        var result = environmentVariables
        if let profile = activeProfile {
            for (key, value) in profile.variables {
                result[key] = value
            }
        }
        return result
    }
}

// MARK: - Change Stats (for sidebar display)

struct WorkspaceChangeStats: Equatable {
    let additions: Int
    let deletions: Int
    let filesChanged: Int

    static let zero = WorkspaceChangeStats(additions: 0, deletions: 0, filesChanged: 0)

    var summary: String {
        if additions == 0 && deletions == 0 { return "No changes" }
        var parts: [String] = []
        if additions > 0 { parts.append("+\(additions)") }
        if deletions > 0 { parts.append("-\(deletions)") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Workspace Sorting

enum WorkspaceSortOrder: String, CaseIterable, Codable {
    case manual = "Manual"
    case name = "Name"
    case dateCreated = "Date Created"
    case status = "Status"
    case changeCount = "Changes"

    var systemImage: String {
        switch self {
        case .manual: return "hand.draw"
        case .name: return "textformat.abc"
        case .dateCreated: return "calendar"
        case .status: return "circle.fill"
        case .changeCount: return "plus.forwardslash.minus"
        }
    }
}

// MARK: - Workspace Filter

enum WorkspaceFilter: String, CaseIterable {
    case active = "Active"
    case archived = "Archived"
    case all = "All"

    var systemImage: String {
        switch self {
        case .active: return "tray.full"
        case .archived: return "archivebox"
        case .all: return "tray.2"
        }
    }
}
