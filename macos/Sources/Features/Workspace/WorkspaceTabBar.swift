import SwiftUI

/// Custom per-workspace tab bar. Only visible when 2+ tabs exist.
/// Styled to match Ghostty's aesthetic — compact, dark, minimal.
struct WorkspaceTabBar: View {
    @ObservedObject var tabGroup: WorkspaceTabGroup
    var onClose: ((UUID) -> Void)?

    var body: some View {
        HStack(spacing: 1) {
            ForEach(tabGroup.tabs) { tab in
                tabItem(tab)
            }

            // New tab button
            Button {
                // Handled by parent via notification
                NotificationCenter.default.post(
                    name: .ghostsetNewWorkspaceTab, object: nil
                )
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(height: 28)
        .background(.bar)
    }

    private func tabItem(_ tab: WorkspaceTabEntry) -> some View {
        let isActive = tab.id == tabGroup.activeTabID

        return HStack(spacing: 4) {
            if let agent = tab.agent {
                Image(systemName: agent.iconName)
                    .font(.system(size: 9))
                    .foregroundColor(isActive ? .accentColor : .secondary)
            }

            Text(tab.title)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)

            if tabGroup.tabs.count > 1 {
                Button {
                    onClose?(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isActive ? Color.white.opacity(0.08) : Color.clear)
        .cornerRadius(5)
        .contentShape(Rectangle())
        .onTapGesture {
            tabGroup.selectTab(id: tab.id)
        }
    }
}

extension Notification.Name {
    static let ghostsetNewWorkspaceTab = Notification.Name("com.ghostset.newWorkspaceTab")
}
