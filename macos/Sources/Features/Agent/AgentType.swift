import Foundation

/// Represents an AI coding agent that can run in a workspace terminal.
/// Agent-agnostic: agents are opaque CLI processes, not embedded.
enum AgentType: Codable, Equatable, Hashable {
    case claude
    case codex
    case copilot
    case opencode
    case gemini
    case cursor
    case custom(String)

    /// Characters that could enable shell injection when passed to a shell.
    private static let shellMetacharacters = CharacterSet(charactersIn: ";|&$`\\(){}")

    /// Strips shell metacharacters from a string to prevent command injection.
    private static func sanitized(_ input: String) -> String {
        input.unicodeScalars.filter { !shellMetacharacters.contains($0) }
            .map { String($0) }
            .joined()
    }

    /// The CLI command to launch this agent with full/dangerous permissions
    var launchCommand: String {
        switch self {
        case .claude: return "claude --dangerously-skip-permissions"
        case .codex: return "codex --full-auto"
        case .copilot: return "gh copilot"
        case .opencode: return "opencode"
        case .gemini: return "gemini"
        case .cursor: return "cursor-agent"
        case .custom(let cmd): return Self.sanitized(cmd)
        }
    }

    /// Short display name for the presets bar
    var displayName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .copilot: return "copilot"
        case .opencode: return "opencode"
        case .gemini: return "gemini"
        case .cursor: return "cursor"
        case .custom(let cmd): return cmd
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .copilot: return "person.badge.shield.checkmark"
        case .opencode: return "square"
        case .gemini: return "diamond"
        case .cursor: return "cursorarrow.rays"
        case .custom: return "terminal.fill"
        }
    }

    /// The CLI command to resume/continue a previous session.
    /// Pass a sessionID for agents that support it (e.g. Claude).
    func resumeCommand(sessionID: String? = nil) -> String {
        switch self {
        case .claude:
            if let id = sessionID {
                return "claude --dangerously-skip-permissions --resume \(id)"
            }
            return "claude --dangerously-skip-permissions --continue"
        case .codex: return "codex --full-auto"
        case .copilot: return "gh copilot"
        case .opencode: return "opencode"
        case .gemini: return "gemini"
        case .cursor: return "cursor-agent"
        case .custom(let cmd): return Self.sanitized(cmd)
        }
    }

    /// All built-in agent types (for presets bar)
    static let builtIn: [AgentType] = [.claude, .codex, .copilot, .opencode, .gemini]
}
