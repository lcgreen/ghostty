import Foundation

/// Represents an AI coding agent that can run in a workspace terminal.
/// Agent-agnostic: agents are opaque CLI processes, not embedded.
enum AgentType: Codable, Equatable, Hashable {
    case claude
    case codex
    case gemini
    case cursor
    case custom(String)

    /// The CLI command to launch this agent
    var launchCommand: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .gemini: return "gemini"
        case .cursor: return "cursor-agent"
        case .custom(let cmd): return cmd
        }
    }

    /// Display name for the UI
    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .cursor: return "Cursor Agent"
        case .custom(let cmd): return cmd
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .claude: return "brain.head.profile"
        case .codex: return "terminal"
        case .gemini: return "sparkles"
        case .cursor: return "cursorarrow.rays"
        case .custom: return "terminal.fill"
        }
    }

    /// All built-in agent types (for picker UI)
    static let builtIn: [AgentType] = [.claude, .codex, .gemini, .cursor]
}
