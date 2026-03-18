import SwiftUI

/// A horizontal tab bar for workspace terminal tabs.
/// Shows one tab per terminal session, with close buttons and a new-tab button.
struct WorkspaceTabBar: View {
    @ObservedObject var panelViewModel: WorkspacePanelViewModel

    var body: some View {
        HStack(spacing: 0) {
            tabStrip
            Spacer()
            newTabButton
        }
        .frame(height: 28)
        .background(.bar)
    }

    // MARK: - Tab Strip

    private var tabStrip: some View {
        HStack(spacing: 1) {
            ForEach(panelViewModel.tabs.tabs) { tab in
                tabItem(tab)
            }
        }
    }

    private func tabItem(_ tab: WorkspaceTab) -> some View {
        let isActive = tab.id == panelViewModel.tabs.activeTabID

        return HStack(spacing: 4) {
            Text(tab.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)

            // Close button (only visible on hover or active)
            Button {
                panelViewModel.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            panelViewModel.selectTab(id: tab.id)
        }
    }

    // MARK: - New Tab Button

    private var newTabButton: some View {
        Button {
            panelViewModel.createTab()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .help("New Tab")
    }
}
