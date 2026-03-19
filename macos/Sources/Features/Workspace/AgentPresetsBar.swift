import SwiftUI

/// Compact horizontal bar of agent presets in the status bar.
/// Tapping one creates a new tab with that agent running.
struct AgentPresetsBar: View {
    var onSelect: (AgentType) -> Void

    @State private var hoveredAgent: String?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AgentType.builtIn, id: \.displayName) { agent in
                agentButton(agent)
            }
        }
    }

    private func agentButton(_ agent: AgentType) -> some View {
        let isHovered = hoveredAgent == agent.displayName

        return Button {
            onSelect(agent)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: agent.iconName)
                    .font(.system(size: 8))
                Text(agent.displayName)
                    .font(.system(size: 10))
            }
            .foregroundStyle(isHovered ? .primary : .tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredAgent = hovering ? agent.displayName : nil
        }
    }
}
