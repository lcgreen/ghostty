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

    init(id: UUID = UUID(), title: String = "Shell", splitLayout: SplitLayout = .leaf(LeafState()), agent: AgentType? = nil, sessionID: String? = nil) {
        self.id = id
        self.title = title
        self.splitLayout = splitLayout
        self.agent = agent
        self.sessionID = sessionID
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

    init(workingDirectory: String? = nil) {
        self.workingDirectory = workingDirectory
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
            return .leaf(LeafState(workingDirectory: surfaceView.pwd))
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
            // Only override working directory if baseConfig doesn't already set one
            // (workspace worktree path takes priority over saved pwd)
            if config.workingDirectory == nil, let pwd = leaf.workingDirectory {
                config.workingDirectory = pwd
            }
            // Only the first leaf runs the agent command
            if !isFirstLeaf {
                config.initialInput = nil
            }
            isFirstLeaf = false
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
