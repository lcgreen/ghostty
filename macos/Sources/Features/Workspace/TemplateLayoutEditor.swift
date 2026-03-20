import SwiftUI

/// Full template layout editor — edit tabs, splits, commands, and visual settings.
struct TemplateLayoutEditor: View {
    @Binding var template: WorkspaceTemplate
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTabIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                // Left: tab list
                tabList
                    .frame(minWidth: 160, maxWidth: 200)

                // Right: selected tab detail
                if let tab = selectedTab {
                    tabDetail(tab)
                } else {
                    Text("Select a tab")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            // Preview + summary
            VStack(spacing: 6) {
                TemplateLayoutPreview(template: template)
                    .frame(height: 40)
                    .padding(.horizontal, 12)
                TemplateLayoutSummary(template: template)
            }
            .padding(.vertical, 8)

            Divider()
            footer
        }
        .frame(width: 560, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var selectedTab: TemplateTab? {
        guard selectedTabIndex >= 0 && selectedTabIndex < template.tabs.count else { return nil }
        return template.tabs[selectedTabIndex]
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            TextField("Template name", text: $template.name)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        .padding(12)
    }

    // MARK: - Tab List

    private var tabList: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { selectedTabIndex },
                set: { selectedTabIndex = $0 }
            )) {
                ForEach(Array(template.tabs.enumerated()), id: \.element.id) { index, tab in
                    tabListRow(tab, index: index)
                        .tag(index)
                }
                .onMove { source, dest in
                    template.tabs.move(fromOffsets: source, toOffset: dest)
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Button { addTab() } label: {
                    Image(systemName: "plus").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                Spacer()
                if template.tabs.count > 1 {
                    Button { removeTab() } label: {
                        Image(systemName: "minus").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
    }

    private func tabListRow(_ tab: TemplateTab, index: Int) -> some View {
        HStack(spacing: 4) {
            if tab.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.orange)
            }
            if let icon = tab.iconOverride {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(tab.colorName.map { TagDefinition.swiftUIColor(for: $0) } ?? .secondary)
            } else if let agent = tab.agent {
                Image(systemName: agent.iconName)
                    .font(.system(size: 9))
                    .foregroundColor(AgentColors.color(for: agent))
            }
            Text(tab.title.isEmpty ? "Tab \(index + 1)" : tab.title)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            if !tab.splits.isEmpty {
                Text("\(tab.splits.count + 1)")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Tab Detail

    private func tabDetail(_ tab: TemplateTab) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Title
                field("Title") {
                    TextField("Tab title", text: tabBinding(\.title))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                // Agent
                field("Agent") {
                    HStack {
                        Menu {
                            Button("None") { updateTab { $0.agent = nil } }
                            Divider()
                            ForEach(AgentType.builtIn, id: \.displayName) { agent in
                                Button(agent.displayName) { updateTab { $0.agent = agent } }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if let agent = tab.agent {
                                    Image(systemName: agent.iconName).font(.system(size: 9))
                                    Text(agent.displayName)
                                } else {
                                    Text("None")
                                }
                                Image(systemName: "chevron.down").font(.system(size: 7))
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.08)).cornerRadius(4)
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                }

                // Command
                if tab.agent == nil {
                    field("Command") {
                        HStack {
                            TextField("e.g., make run", text: tabBinding(\.command, default: ""))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                            Toggle("Auto-run", isOn: tabBinding(\.autoRun))
                                .toggleStyle(.checkbox)
                                .font(.system(size: 10))
                        }
                    }
                }

                // Visual
                HStack(spacing: 16) {
                    field("Pin") {
                        Toggle("Pinned", isOn: tabBinding(\.isPinned))
                            .toggleStyle(.checkbox)
                            .font(.system(size: 10))
                    }

                    field("Color") {
                        HStack(spacing: 3) {
                            Button { updateTab { $0.colorName = nil } } label: {
                                Circle().strokeBorder(.secondary, lineWidth: 0.5).frame(width: 12, height: 12)
                            }.buttonStyle(.plain)
                            ForEach(["blue", "green", "orange", "red", "purple", "teal"], id: \.self) { c in
                                Button { updateTab { $0.colorName = c } } label: {
                                    Circle().fill(TagDefinition.swiftUIColor(for: c)).frame(width: 12, height: 12)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: tab.colorName == c ? 1.5 : 0))
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    field("Icon") {
                        Menu {
                            Button("Default") { updateTab { $0.iconOverride = nil } }
                            Divider()
                            ForEach([
                                ("terminal", "Terminal"), ("globe", "Web"), ("server.rack", "Server"),
                                ("hammer", "Build"), ("testtube.2", "Test"), ("doc.text", "Docs"),
                            ], id: \.0) { icon, label in
                                Button(label) { updateTab { $0.iconOverride = icon } }
                            }
                        } label: {
                            Image(systemName: tab.iconOverride ?? "square.dashed")
                                .font(.system(size: 10))
                                .frame(width: 20, height: 20)
                                .background(Color.secondary.opacity(0.08)).cornerRadius(3)
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                }

                Divider()

                // Splits
                field("Splits") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(tab.splits.enumerated()), id: \.element.id) { splitIdx, split in
                            splitRow(splitIdx, split)
                        }
                        Button("Add Split") { addSplit() }
                            .font(.system(size: 10))
                            .buttonStyle(.bordered).controlSize(.mini)
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Split Row

    private func splitRow(_ index: Int, _ split: TemplateSplit) -> some View {
        HStack(spacing: 6) {
            // Direction
            Button {
                updateSplit(index) { $0 = TemplateSplit(
                    command: $0.command, autoRun: $0.autoRun, subdirectory: $0.subdirectory,
                    direction: $0.direction == .horizontal ? .vertical : .horizontal
                )}
            } label: {
                Image(systemName: split.direction == .horizontal ? "rectangle.split.1x2" : "rectangle.split.2x1")
                    .font(.system(size: 10))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(split.direction == .horizontal ? "Horizontal" : "Vertical")

            // Command
            TextField("command", text: splitBinding(index, \.command, default: ""))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))

            // Subdirectory
            TextField("subdir", text: splitBinding(index, \.subdirectory, default: ""))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 80)

            // Auto-run
            Toggle("", isOn: splitBinding(index, \.autoRun))
                .toggleStyle(.checkbox)
                .help("Auto-run")

            // Remove
            Button { removeSplit(index) } label: {
                Image(systemName: "xmark").font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(4)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Copy JSON") { copyJSON() }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 11))
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: - Actions

    private func addTab() {
        template.tabs.append(TemplateTab(title: "New Tab"))
        selectedTabIndex = template.tabs.count - 1
    }

    private func removeTab() {
        guard selectedTabIndex < template.tabs.count else { return }
        template.tabs.remove(at: selectedTabIndex)
        selectedTabIndex = min(selectedTabIndex, max(template.tabs.count - 1, 0))
    }

    private func addSplit() {
        guard selectedTabIndex < template.tabs.count else { return }
        template.tabs[selectedTabIndex].splits.append(
            TemplateSplit(command: "", autoRun: true)
        )
    }

    private func removeSplit(_ index: Int) {
        guard selectedTabIndex < template.tabs.count else { return }
        template.tabs[selectedTabIndex].splits.remove(at: index)
    }

    private func updateTab(_ update: (inout TemplateTab) -> Void) {
        guard selectedTabIndex < template.tabs.count else { return }
        update(&template.tabs[selectedTabIndex])
    }

    private func updateSplit(_ index: Int, _ update: (inout TemplateSplit) -> Void) {
        guard selectedTabIndex < template.tabs.count,
              index < template.tabs[selectedTabIndex].splits.count else { return }
        update(&template.tabs[selectedTabIndex].splits[index])
    }

    private func copyJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(template),
           let json = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json, forType: .string)
        }
    }

    // MARK: - Bindings

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            content()
        }
    }

    private func tabBinding<T>(_ keyPath: WritableKeyPath<TemplateTab, T>) -> Binding<T> {
        Binding(
            get: { selectedTabIndex < template.tabs.count ? template.tabs[selectedTabIndex][keyPath: keyPath] : template.tabs[0][keyPath: keyPath] },
            set: { if selectedTabIndex < template.tabs.count { template.tabs[selectedTabIndex][keyPath: keyPath] = $0 } }
        )
    }

    private func tabBinding(_ keyPath: WritableKeyPath<TemplateTab, String?>, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { (selectedTabIndex < template.tabs.count ? template.tabs[selectedTabIndex][keyPath: keyPath] : nil) ?? defaultValue },
            set: { if selectedTabIndex < template.tabs.count { template.tabs[selectedTabIndex][keyPath: keyPath] = $0.isEmpty ? nil : $0 } }
        )
    }

    private func splitBinding<T>(_ index: Int, _ keyPath: WritableKeyPath<TemplateSplit, T>) -> Binding<T> {
        Binding(
            get: { template.tabs[selectedTabIndex].splits[index][keyPath: keyPath] },
            set: { template.tabs[selectedTabIndex].splits[index][keyPath: keyPath] = $0 }
        )
    }

    private func splitBinding(_ index: Int, _ keyPath: WritableKeyPath<TemplateSplit, String?>, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { template.tabs[selectedTabIndex].splits[index][keyPath: keyPath] ?? defaultValue },
            set: { template.tabs[selectedTabIndex].splits[index][keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }
}
