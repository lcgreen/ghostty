import Foundation

// MARK: - Workspace

/// A single isolated workspace backed by a git worktree.
/// Each workspace has its own terminal surface and optional agent.
struct Workspace: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let repoPath: String
    let worktreePath: String
    let branch: String
    let createdAt: Date
    var agent: AgentType?
    var status: WorkspaceStatus

    init(
        name: String,
        repoPath: String,
        worktreePath: String,
        branch: String,
        agent: AgentType? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.repoPath = repoPath
        self.worktreePath = worktreePath
        self.branch = branch
        self.createdAt = Date()
        self.agent = agent
        self.status = .creating
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

// MARK: - Workspace Configuration

/// Stored in ~/.ghostset/config.json per-repo
struct WorkspaceConfig: Codable {
    var defaultAgent: AgentType?
    var setupCommand: String?
    var teardownCommand: String?
    var environmentVariables: [String: String]

    init(
        defaultAgent: AgentType? = nil,
        setupCommand: String? = nil,
        teardownCommand: String? = nil,
        environmentVariables: [String: String] = [:]
    ) {
        self.defaultAgent = defaultAgent
        self.setupCommand = setupCommand
        self.teardownCommand = teardownCommand
        self.environmentVariables = environmentVariables
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
