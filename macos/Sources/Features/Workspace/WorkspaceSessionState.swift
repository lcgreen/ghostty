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

    init(
        id: UUID = UUID(),
        title: String = "",
        splitLayout: SplitLayout = .leaf(LeafState()),
        agent: AgentType? = nil,
        sessionID: String? = nil,
        isPinned: Bool = false,
        colorName: String? = nil,
        iconOverride: String? = nil
    ) {
        self.id = id
        self.title = title
        self.splitLayout = splitLayout
        self.agent = agent
        self.sessionID = sessionID
        self.isPinned = isPinned
        self.colorName = colorName
        self.iconOverride = iconOverride
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
    }
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

    init(workingDirectory: String? = nil, lastTitle: String? = nil) {
        self.workingDirectory = workingDirectory
        self.lastTitle = lastTitle
    }

    // Backward-compatible decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        lastTitle = try container.decodeIfPresent(String.self, forKey: .lastTitle)
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
        isFirstLeaf: inout Bool
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

            // Pre-fill last command for ALL leaves (agent or not)
            // If no agent initialInput was set, use the last title as a command hint
            if config.initialInput == nil, let title = leaf.lastTitle {
                if !title.contains("@") && !title.hasPrefix("/") && !title.hasPrefix("~") {
                    config.initialInput = title
                }
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
                left: split.left.toNode(app: app, baseConfig: baseConfig, isFirstLeaf: &isFirstLeaf),
                right: split.right.toNode(app: app, baseConfig: baseConfig, isFirstLeaf: &isFirstLeaf)
            ))
        }
    }

    /// Rebuild a live SplitTree from a persisted layout.
    func toSplitTree(
        app: ghostty_app_t,
        baseConfig: Ghostty.SurfaceConfiguration? = nil
    ) -> SplitTree<Ghostty.SurfaceView> {
        var isFirstLeaf = true
        return SplitTree(root: toNode(app: app, baseConfig: baseConfig, isFirstLeaf: &isFirstLeaf), zoomed: nil)
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
