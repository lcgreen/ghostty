import Foundation
import GhosttyKit

/// Captures agent session IDs from terminal output by polling the screen buffer.
/// Claude Code prints a session ID in its startup banner that can be used for
/// precise `--resume <id>` on relaunch.
enum AgentSessionCapture {

    /// Pattern to match Claude Code's session ID from terminal output.
    /// Claude outputs something like: "Session: abc123def456"
    /// or includes it in the REPL prompt area.
    private static let claudeSessionPattern = try! NSRegularExpression(
        pattern: #"(?:session|Session|SESSION)[:\s]+([a-f0-9-]{8,})"#
    )

    /// Scan the visible terminal buffer for a Claude session ID.
    /// Returns the session ID string if found, nil otherwise.
    static func captureSessionID(
        from surface: ghostty_surface_t,
        agent: AgentType
    ) -> String? {
        switch agent {
        case .claude:
            return scanForPattern(surface: surface, pattern: claudeSessionPattern)
        default:
            return nil
        }
    }

    /// Read the viewport text and search for a regex match.
    private static func scanForPattern(
        surface: ghostty_surface_t,
        pattern: NSRegularExpression
    ) -> String? {
        var text = ghostty_text_s()
        let sel = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0, y: 0),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: 0, y: 0),
            rectangle: false
        )

        guard ghostty_surface_read_text(surface, sel, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }

        let content = String(cString: text.text)
        let range = NSRange(content.startIndex..., in: content)

        guard let match = pattern.firstMatch(in: content, range: range),
              match.numberOfRanges >= 2,
              let idRange = Range(match.range(at: 1), in: content) else {
            return nil
        }

        return String(content[idRange])
    }
}
