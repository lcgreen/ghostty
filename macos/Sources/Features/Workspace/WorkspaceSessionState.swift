import Foundation
import GhosttyKit

/// Codable representation of a workspace's terminal session layout.
/// Used to persist and restore tab/split state across app restarts.
struct WorkspaceSessionState: Codable {
    let workspaceID: UUID
    let tabs: [TabSessionState]
    let activeTabIndex: Int
    let savedAt: Date

    init(workspaceID: UUID, tabs: [TabSessionState], activeTabIndex: Int = 0) {
        self.workspaceID = workspaceID
        self.tabs = tabs
        self.activeTabIndex = activeTabIndex
        self.savedAt = Date()
    }
}

/// Persisted state for a single terminal tab.
struct TabSessionState: Codable {
    let id: UUID
    let title: String
    let splitLayout: SplitLayout
    let agent: AgentType?
    let sessionID: String?
    let isPinned: Bool
    let colorName: String?
    let iconOverride: String?
    /// Commands for each split pane (indexed by position in tree traversal).
    let splitCommands: [SplitCommand]

    init(
        id: UUID = UUID(),
        title: String = "",
        splitLayout: SplitLayout = .leaf(LeafState()),
        agent: AgentType? = nil,
        sessionID: String? = nil,
        isPinned: Bool = false,
        colorName: String? = nil,
        iconOverride: String? = nil,
        splitCommands: [SplitCommand] = []
    ) {
        self.id = id
        self.title = title
        self.splitLayout = splitLayout
        self.agent = agent
        self.sessionID = sessionID
        self.isPinned = isPinned
        self.colorName = colorName
        self.iconOverride = iconOverride
        self.splitCommands = splitCommands
    }

    // Backward-compatible decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        splitLayout = try container.decode(SplitLayout.self, forKey: .splitLayout)
        agent = try container.decodeIfPresent(AgentType.self, forKey: .agent)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        colorName = try container.decodeIfPresent(String.self, forKey: .colorName)
        iconOverride = try container.decodeIfPresent(String.self, forKey: .iconOverride)
        splitCommands = try container.decodeIfPresent([SplitCommand].self, forKey: .splitCommands) ?? []
    }
}

/// A command associated with a split pane, persisted for auto-run on restore.
struct SplitCommand: Codable {
    let command: String
    let autoRun: Bool
}

/// Recursive representation of a split tree layout (without live surface references).
/// Stores only the data needed to recreate the layout: working directories and split ratios.
indirect enum SplitLayout: Codable {
    case leaf(LeafState)
    case split(SplitState)
}

/// A terminal leaf in the persisted split tree.
struct LeafState: Codable {
    let workingDirectory: String?
    /// The last terminal title — used to suggest re-running the last command on restore.
    let lastTitle: String?
    /// The command to auto-run on restore (from template).
    let command: String?
    /// Whether the command should auto-execute on restore.
    let autoRun: Bool

    init(workingDirectory: String? = nil, lastTitle: String? = nil, command: String? = nil, autoRun: Bool = false) {
        self.workingDirectory = workingDirectory
        self.lastTitle = lastTitle
        self.command = command
        self.autoRun = autoRun
    }

    // Backward-compatible decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        lastTitle = try container.decodeIfPresent(String.self, forKey: .lastTitle)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        autoRun = try container.decodeIfPresent(Bool.self, forKey: .autoRun) ?? false
    }
}

/// A split node in the persisted split tree.
struct SplitState: Codable {
    let direction: SplitDirection
    let ratio: Double
    let left: SplitLayout
    let right: SplitLayout
}

/// Direction of a split (matches SplitTree.Node.Split.Direction).
enum SplitDirection: String, Codable {
    case horizontal
    case vertical
}

// MARK: - SplitLayout from live SplitTree

extension SplitLayout {
    /// Extract a persistable layout from a live split tree node.
    static func from(node: SplitTree<Ghostty.SurfaceView>.Node) -> SplitLayout {
        switch node {
        case .leaf(let surfaceView):
            return .leaf(LeafState(
                workingDirectory: surfaceView.pwd,
                lastTitle: surfaceView.title.isEmpty ? nil : surfaceView.title
            ))
        case .split(let split):
            let dir: SplitDirection = switch split.direction {
            case .horizontal: .horizontal
            case .vertical: .vertical
            }
            return .split(SplitState(
                direction: dir,
                ratio: split.ratio,
                left: .from(node: split.left),
                right: .from(node: split.right)
            ))
        }
    }

    /// Extract a persistable layout from a live split tree.
    static func from(tree: SplitTree<Ghostty.SurfaceView>) -> SplitLayout? {
        guard let root = tree.root else { return nil }
        return from(node: root)
    }

    /// Rebuild a live SplitTree node from a persisted layout.
    /// Only the first leaf gets `initialInput` (so agents launch once, not per-split).
    func toNode(
        app: ghostty_app_t,
        baseConfig: Ghostty.SurfaceConfiguration? = nil,
        isFirstLeaf: inout Bool,
        splitCommands: inout ArraySlice<SplitCommand>
    ) -> SplitTree<Ghostty.SurfaceView>.Node {
        switch self {
        case .leaf(let leaf):
            var config = baseConfig ?? Ghostty.SurfaceConfiguration()
            // Use saved pwd (terminal's last directory) — overrides workspace root
            if let pwd = leaf.workingDirectory, !pwd.isEmpty {
                config.workingDirectory = pwd
            }
            // Only the first leaf runs the agent command
            if !isFirstLeaf {
                config.initialInput = nil
            }
            isFirstLeaf = false

            // Auto-run saved command from template, or pre-fill last title as hint
            if config.initialInput == nil {
                if let splitCmd = splitCommands.first {
                    splitCommands = splitCommands.dropFirst()
                    config.initialInput = splitCmd.command + (splitCmd.autoRun ? "\n" : "")
                } else if let title = leaf.lastTitle {
                    if !title.contains("@") && !title.hasPrefix("/") && !title.hasPrefix("~") {
                        config.initialInput = title
                    }
                }
            } else {
                // Consume the command even if not used (agent leaf)
                if !splitCommands.isEmpty { splitCommands = splitCommands.dropFirst() }
            }
            return .leaf(view: Ghostty.SurfaceView(app, baseConfig: config))

        case .split(let split):
            let direction: SplitTree<Ghostty.SurfaceView>.Direction = switch split.direction {
            case .horizontal: .horizontal
            case .vertical: .vertical
            }
            return .split(.init(
                direction: direction,
                ratio: split.ratio,
                left: split.left.toNode(app: app, baseConfig: baseConfig, isFirstLeaf: &isFirstLeaf, splitCommands: &splitCommands),
                right: split.right.toNode(app: app, baseConfig: baseConfig, isFirstLeaf: &isFirstLeaf, splitCommands: &splitCommands)
            ))
        }
    }

    /// Rebuild a live SplitTree from a persisted layout.
    func toSplitTree(
        app: ghostty_app_t,
        baseConfig: Ghostty.SurfaceConfiguration? = nil,
        splitCommands: [SplitCommand] = []
    ) -> SplitTree<Ghostty.SurfaceView> {
        var isFirstLeaf = true
        var cmds = splitCommands[...]
        return SplitTree(root: toNode(app: app, baseConfig: baseConfig, isFirstLeaf: &isFirstLeaf, splitCommands: &cmds), zoomed: nil)
    }
}

// MARK: - Command History

/// A single command history entry.
struct CommandHistoryEntry: Codable {
    let command: String
    let workingDirectory: String
    let timestamp: Date
    let workspaceID: UUID
}
