import SwiftUI
import UniformTypeIdentifiers

/// Per-workspace tab bar — full-width tabs matching Ghostty's native titlebar style.
struct WorkspaceTabBar: View {
    @ObservedObject var tabGroup: WorkspaceTabGroup
    var onClose: ((UUID) -> Void)?
    var onNew: (() -> Void)?
    var workspaces: [Workspace] = []
    var onMoveToWorkspace: ((UUID, UUID) -> Void)?
    var onTearOff: ((UUID) -> Void)?

    @State private var draggedTabID: UUID?

    private var useScroll: Bool { tabGroup.tabs.count > 6 }

    var body: some View {
        HStack(spacing: 0) {
            if useScroll {
                ScrollView(.horizontal, showsIndicators: false) {
                    tabsContent
                }
            } else {
                tabsContent
            }

            Button { onNew?() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .padding(.vertical, 3)
    }

    private var tabsContent: some View {
        HStack(spacing: 2) {
            ForEach(Array(tabGroup.tabs.enumerated()), id: \.element.id) { index, tab in
                tabItem(tab, index: index)
                    .frame(maxWidth: tab.isPinned ? 40 : (useScroll ? 220 : .infinity))
                    .opacity(draggedTabID == tab.id ? 0.4 : 1.0)
                    .onDrag {
                        draggedTabID = tab.id
                        return NSItemProvider(object: tab.id.uuidString as NSString)
                    }
                    .onDrop(of: [.utf8PlainText], delegate: TabDropDelegate(
                        tabGroup: tabGroup,
                        targetID: tab.id,
                        draggedTabID: $draggedTabID
                    ))
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Tab Item

    private func tabItem(_ tab: WorkspaceTabEntry, index: Int) -> some View {
        let isActive = tab.id == tabGroup.activeTabID
        let tabColor = tab.colorName.map { TagDefinition.swiftUIColor(for: $0) }

        return Button {
            tabGroup.selectTab(id: tab.id)
        } label: {
            HStack(spacing: 0) {
                if tab.isPinned {
                    Spacer(minLength: 0)
                    if let agent = tab.agent {
                        Image(systemName: agent.iconName)
                            .font(.system(size: 10))
                            .foregroundColor(AgentColors.color(for: agent))
                    } else {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                } else {
                    if tabGroup.tabs.count > 1 {
                        Button { onClose?(tab.id) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 6)
                    }

                    Spacer(minLength: 4)

                    if let icon = tab.iconOverride {
                        Image(systemName: icon)
                            .font(.system(size: 9))
                            .foregroundColor(tabColor ?? .secondary)
                            .padding(.trailing, 4)
                    } else if let agent = tab.agent {
                        Image(systemName: agent.iconName)
                            .font(.system(size: 9))
                            .foregroundColor(AgentColors.color(for: agent))
                            .padding(.trailing, 4)
                    }

                    Text(tab.title.isEmpty ? "…" : tab.title)
                        .font(.system(size: 12))
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    if index < 9 {
                        Text("⌘\(index + 1)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(isActive ? .tertiary : .quaternary)
                            .padding(.trailing, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    isActive
                        ? (tabColor?.opacity(0.12) ?? Color.primary.opacity(0.1))
                        : Color.clear
                )
            )
            .overlay(
                Group {
                    if let color = tabColor, isActive {
                        VStack {
                            Spacer()
                            Capsule().fill(color).frame(height: 2)
                                .padding(.horizontal, 12)
                        }
                    }
                }
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu { tabContextMenu(tab, index: index) }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func tabContextMenu(_ tab: WorkspaceTabEntry, index: Int) -> some View {
        Button("Close Tab") { onClose?(tab.id) }
            .disabled(tabGroup.tabs.count <= 1 || tab.isPinned)
        Button("Close Other Tabs") { closeOthers(except: tab.id) }
            .disabled(tabGroup.tabs.count <= 1)
        Button("Close Tabs to the Right") { closeRight(of: index) }
            .disabled(index >= tabGroup.tabs.count - 1)

        Divider()

        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
            tabGroup.togglePin(id: tab.id)
        }

        Divider()

        Button("Move Left") {
            tabGroup.moveTab(id: tab.id, toIndex: index - 1)
        }
        .disabled(index == 0)

        Button("Move Right") {
            tabGroup.moveTab(id: tab.id, toIndex: index + 1)
        }
        .disabled(index >= tabGroup.tabs.count - 1)

        Divider()

        Menu("Tab Color") {
            Button("None") { tabGroup.setTabColor(id: tab.id, color: nil) }
            Divider()
            ForEach(["blue", "green", "orange", "red", "purple", "teal", "pink", "indigo"], id: \.self) { color in
                Button {
                    tabGroup.setTabColor(id: tab.id, color: color)
                } label: {
                    HStack {
                        Circle().fill(TagDefinition.swiftUIColor(for: color)).frame(width: 8, height: 8)
                        Text(color.capitalized)
                    }
                }
            }
        }

        Menu("Tab Icon") {
            Button("Default") { tabGroup.setTabIcon(id: tab.id, icon: nil) }
            Divider()
            ForEach([
                ("terminal", "Terminal"), ("globe", "Web"), ("server.rack", "Server"),
                ("hammer", "Build"), ("testtube.2", "Test"), ("doc.text", "Docs"),
                ("ant", "Debug"), ("bolt", "Script"),
            ], id: \.0) { icon, label in
                Button { tabGroup.setTabIcon(id: tab.id, icon: icon) } label: {
                    Label(label, systemImage: icon)
                }
            }
        }

        Divider()

        Button("Detach to Window") { onTearOff?(tab.id) }

        if !workspaces.isEmpty {
            Menu("Move to Workspace") {
                ForEach(workspaces) { ws in
                    Button(ws.name) { onMoveToWorkspace?(tab.id, ws.id) }
                }
            }
        }

        Divider()

        Button("Duplicate Tab") { onNew?() }
        Button("New Shell Tab") { onNew?() }
    }

    private func closeOthers(except id: UUID) {
        let toClose = tabGroup.tabs.filter { $0.id != id && !$0.isPinned }.map(\.id)
        for tabID in toClose { onClose?(tabID) }
    }

    private func closeRight(of index: Int) {
        let toClose = tabGroup.tabs.suffix(from: index + 1).filter { !$0.isPinned }.map(\.id)
        for tabID in toClose { onClose?(tabID) }
    }
}

// MARK: - Drop Delegate

struct TabDropDelegate: DropDelegate {
    let tabGroup: WorkspaceTabGroup
    let targetID: UUID
    @Binding var draggedTabID: UUID?

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedTabID, dragged != targetID else { return }
        guard let targetIndex = tabGroup.tabs.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            tabGroup.moveTab(id: dragged, toIndex: targetIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedTabID != nil
    }
}
