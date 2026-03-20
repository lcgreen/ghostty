import SwiftUI
import GhosttyKit

/// A lightweight TerminalViewModel for workspace terminal panels.
/// Provides the split tree and state required by TerminalView without
/// needing a full BaseTerminalController / NSWindowController.
final class WorkspaceTerminalViewModel: ObservableObject, TerminalViewModel {

    /// The tree of terminal surfaces (splits) within this workspace panel.
    @Published var surfaceTree: SplitTree<Ghostty.SurfaceView> = .init()

    /// Whether the command palette is showing.
    @Published var commandPaletteIsShowing: Bool = false

    /// The currently focused surface (for tab title sync in splits).
    weak var focusedSurface: Ghostty.SurfaceView?

    /// Update overlay (not used in workspace context).
    var updateOverlayIsVisible: Bool { false }
}
