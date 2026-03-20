import SwiftUI

/// Miniature visual preview of a template's tab/split layout.
struct TemplateLayoutPreview: View {
    let template: WorkspaceTemplate

    var body: some View {
        if template.tabs.isEmpty {
            // Legacy template — single pane
            singlePane(agent: template.agent, command: nil)
        } else {
            HStack(spacing: 2) {
                ForEach(template.tabs) { tab in
                    tabPreview(tab)
                }
            }
        }
    }

    private func tabPreview(_ tab: TemplateTab) -> some View {
        VStack(spacing: 1) {
            // Tab header
            HStack(spacing: 2) {
                if tab.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 5))
                        .foregroundColor(.orange)
                }
                Text(tab.title.isEmpty ? (tab.agent?.displayName ?? "Shell") : tab.title)
                    .font(.system(size: 6, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 1)

            // Split layout
            if tab.splits.isEmpty {
                singlePane(agent: tab.agent, command: tab.command)
            } else {
                splitPanes(tab)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(tabColor(tab).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(tabColor(tab).opacity(0.2), lineWidth: 0.5)
        )
    }

    private func splitPanes(_ tab: TemplateTab) -> some View {
        // Main pane + splits
        let mainCommand = tab.command ?? tab.agent?.displayName
        let allPanes = [(cmd: mainCommand, dir: SplitDirection.horizontal)] +
            tab.splits.map { (cmd: $0.command, dir: $0.direction) }

        // Simple layout: alternate horizontal/vertical
        return VStack(spacing: 1) {
            // Group by direction
            let horizontalPanes = allPanes.filter { $0.dir == .horizontal || $0.dir == allPanes.first?.dir }
            let verticalPanes = allPanes.filter { $0.dir == .vertical && $0.dir != allPanes.first?.dir }

            HStack(spacing: 1) {
                ForEach(Array(allPanes.enumerated()), id: \.offset) { _, pane in
                    commandPane(pane.cmd)
                }
            }
        }
    }

    private func singlePane(agent: AgentType?, command: String?) -> some View {
        commandPane(agent?.displayName ?? command)
    }

    private func commandPane(_ command: String?) -> some View {
        Text(command ?? "shell")
            .font(.system(size: 5))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 14)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(1)
    }

    private func tabColor(_ tab: TemplateTab) -> Color {
        if let color = tab.colorName {
            return TagDefinition.swiftUIColor(for: color)
        }
        if let agent = tab.agent {
            return AgentColors.color(for: agent)
        }
        return .secondary
    }
}

/// Summary text for a template layout.
struct TemplateLayoutSummary: View {
    let template: WorkspaceTemplate

    var body: some View {
        let tabCount = max(template.tabs.count, 1)
        let splitCount = template.tabs.reduce(0) { $0 + $1.splits.count }
        let commandCount = template.tabs.reduce(0) { count, tab in
            var c = count
            if tab.command != nil || tab.agent != nil { c += 1 }
            c += tab.splits.filter { $0.command != nil }.count
            return c
        }
        let pinnedCount = template.tabs.filter(\.isPinned).count

        HStack(spacing: 4) {
            Text("\(tabCount) tab\(tabCount == 1 ? "" : "s")")
            if splitCount > 0 {
                Text("·")
                Text("\(splitCount) split\(splitCount == 1 ? "" : "s")")
            }
            if commandCount > 0 {
                Text("·")
                Text("\(commandCount) cmd\(commandCount == 1 ? "" : "s")")
            }
            if pinnedCount > 0 {
                Text("·")
                Text("\(pinnedCount) pinned")
            }
        }
        .font(.system(size: 8))
        .foregroundStyle(.tertiary)
    }
}
