import SwiftUI

/// Custom per-workspace tab bar. Compact, dark, minimal — matches Ghostty's aesthetic.
struct WorkspaceTabBar: View {
    @ObservedObject var tabGroup: WorkspaceTabGroup
    var onClose: ((UUID) -> Void)?

    @State private var hoveredTabID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabGroup.tabs) { tab in
                tabItem(tab)
            }

            newTabButton
            Spacer()
        }
        .frame(height: 30)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Tab Item

    private func tabItem(_ tab: WorkspaceTabEntry) -> some View {
        let isActive = tab.id == tabGroup.activeTabID
        let isHovered = tab.id == hoveredTabID

        return HStack(spacing: 5) {
            if let agent = tab.agent {
                Image(systemName: agent.iconName)
                    .font(.system(size: 9))
                    .foregroundColor(isActive ? .accentColor : .secondary)
            }

            Text(tab.title)
                .font(.system(size: 11, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)

            if tabGroup.tabs.count > 1 && (isActive || isHovered) {
                Button {
                    onClose?(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.white.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                tabGroup.selectTab(id: tab.id)
            }
        }
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : nil
        }
    }

    // MARK: - New Tab Button

    private var newTabButton: some View {
        Button {
            NotificationCenter.default.post(
                name: .ghostsetNewWorkspaceTab, object: nil
            )
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
    }
}

extension Notification.Name {
    static let ghostsetNewWorkspaceTab = Notification.Name("com.ghostset.newWorkspaceTab")
}
