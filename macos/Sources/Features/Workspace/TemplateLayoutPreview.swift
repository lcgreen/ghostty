import SwiftUI

/// Miniature visual preview of a template's tab/split layout.
struct TemplateLayoutPreview: View {
    let template: WorkspaceTemplate

    var body: some View {
        if template.tabs.isEmpty {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.06))
                .overlay(Text("shell").font(.system(size: 6)).foregroundStyle(.tertiary))
        } else {
            HStack(spacing: 3) {
                ForEach(template.tabs) { tab in
                    tabPreview(tab)
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func tabPreview(_ tab: TemplateTab) -> some View {
        let color = tabColor(tab)
        let name = tab.title.isEmpty ? (tab.agent?.displayName ?? "Shell") : tab.title
        let splitCount = tab.splits.count + (tab.layout != nil ? countPaneSplits(tab.layout!) : 0)

        return VStack(spacing: 0) {
            // Tab header
            HStack(spacing: 1) {
                if tab.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 4))
                        .foregroundColor(.orange)
                }
                Text(name)
                    .font(.system(size: 6, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
            .background(color.opacity(0.15))

            // Pane structure — show splits as blocks, not text
            if splitCount > 0 {
                splitStructure(tab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(1)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(color.opacity(0.25), lineWidth: 0.5)
        )
    }

    /// Visual split structure — colored blocks showing the layout
    @ViewBuilder
    private func splitStructure(_ tab: TemplateTab) -> some View {
        if let layout = tab.layout {
            paneStructure(layout, color: tabColor(tab))
        } else {
            // Build flat splits respecting direction
            flatSplitStructure(tab)
        }
    }

    private func paneStructure(_ pane: TemplatePane, color: Color) -> AnyView {
        switch pane {
        case .terminal:
            return AnyView(
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(0.1))
            )
        case .split(let split):
            if split.direction == .horizontal {
                return AnyView(HStack(spacing: 1) {
                    paneStructure(split.first, color: color)
                    paneStructure(split.second, color: color)
                })
            } else {
                return AnyView(VStack(spacing: 1) {
                    paneStructure(split.first, color: color)
                    paneStructure(split.second, color: color)
                })
            }
        }
    }

    private func countPaneSplits(_ pane: TemplatePane) -> Int {
        switch pane {
        case .terminal: return 0
        case .split(let s): return 1 + countPaneSplits(s.first) + countPaneSplits(s.second)
        }
    }

    private func flatSplitStructure(_ tab: TemplateTab) -> AnyView {
        let color = tabColor(tab)
        let mainBlock = AnyView(RoundedRectangle(cornerRadius: 1).fill(color.opacity(0.12)))

        // Build nested structure from flat splits
        var result = mainBlock
        for split in tab.splits {
            let newBlock = AnyView(RoundedRectangle(cornerRadius: 1).fill(color.opacity(0.08)))
            if split.direction == .horizontal {
                result = AnyView(HStack(spacing: 1) { result; newBlock })
            } else {
                result = AnyView(VStack(spacing: 1) { result; newBlock })
            }
        }
        return result
    }

    // MARK: - Helpers

    private func tabColor(_ tab: TemplateTab) -> Color {
        if let c = tab.colorName { return TagDefinition.swiftUIColor(for: c) }
        if let a = tab.agent { return AgentColors.color(for: a) }
        return .secondary
    }
}

/// Summary text for a template layout.
struct TemplateLayoutSummary: View {
    let template: WorkspaceTemplate

    var body: some View {
        let tabCount = max(template.tabs.count, 1)
        let splitCount = countSplits()
        let commandCount = countCommands()
        let pinnedCount = template.tabs.filter(\.isPinned).count

        HStack(spacing: 4) {
            Text("\(tabCount) tab\(tabCount == 1 ? "" : "s")")
            if splitCount > 0 { Text("·"); Text("\(splitCount) split\(splitCount == 1 ? "" : "s")") }
            if commandCount > 0 { Text("·"); Text("\(commandCount) cmd\(commandCount == 1 ? "" : "s")") }
            if pinnedCount > 0 { Text("·"); Text("\(pinnedCount) pinned") }
        }
        .font(.system(size: 8))
        .foregroundStyle(.tertiary)
    }

    private func countSplits() -> Int {
        template.tabs.reduce(0) { total, tab in
            if let layout = tab.layout {
                return total + countPaneSplits(layout)
            }
            return total + tab.splits.count
        }
    }

    private func countPaneSplits(_ pane: TemplatePane) -> Int {
        switch pane {
        case .terminal: return 0
        case .split(let s): return 1 + countPaneSplits(s.first) + countPaneSplits(s.second)
        }
    }

    private func countCommands() -> Int {
        template.tabs.reduce(0) { total, tab in
            var c = total
            if tab.command != nil || tab.agent != nil { c += 1 }
            if let layout = tab.layout {
                c += countPaneCommands(layout) - (tab.command != nil ? 1 : 0)
            } else {
                c += tab.splits.filter { $0.command != nil }.count
            }
            return c
        }
    }

    private func countPaneCommands(_ pane: TemplatePane) -> Int {
        switch pane {
        case .terminal(let leaf): return leaf.command != nil ? 1 : 0
        case .split(let s): return countPaneCommands(s.first) + countPaneCommands(s.second)
        }
    }
}
