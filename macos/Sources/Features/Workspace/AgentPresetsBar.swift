import SwiftUI

/// A compact horizontal bar of agent presets. Tapping one launches that
/// agent in the current terminal surface.
struct AgentPresetsBar: View {
    var onSelect: (AgentType) -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Separator from sidebar
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 1, height: 14)
                .padding(.trailing, 8)

            ForEach(AgentType.builtIn, id: \.displayName) { agent in
                Button {
                    onSelect(agent)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: agent.iconName)
                            .font(.system(size: 9))
                        Text(agent.displayName)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
    }
}
