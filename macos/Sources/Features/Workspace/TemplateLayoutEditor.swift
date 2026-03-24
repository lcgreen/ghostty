import SwiftUI

/// Full template layout editor — edit tabs, splits, commands, and visual settings.
struct TemplateLayoutEditor: View {
    var original: WorkspaceTemplate
    var onSave: (WorkspaceTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var template: WorkspaceTemplate
    @State private var selectedTabID: UUID?
    @State private var showingCommands = false

    init(original: WorkspaceTemplate, onSave: @escaping (WorkspaceTemplate) -> Void) {
        self.original = original
        self.onSave = onSave
        self._template = State(initialValue: original)
        self._selectedTabID = State(initialValue: original.tabs.first?.id)
    }

    private var selectedTabIndex: Int {
        guard let id = selectedTabID else { return 0 }
        return template.tabs.firstIndex(where: { $0.id == id }) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                TextField("Template name", text: $template.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(12)

            Divider()

            // Main content: tab list + detail
            HStack(spacing: 0) {
                // Left: tab list
                VStack(spacing: 0) {
                    List(selection: $selectedTabID) {
                        ForEach(template.tabs) { tab in
                            tabListRow(tab)
                                .tag(tab.id)
                        }
                        .onMove { source, dest in
                            template.tabs.move(fromOffsets: source, toOffset: dest)
                        }
                    }
                    .listStyle(.sidebar)

                    Divider()

                    HStack(spacing: 4) {
                        Button { addTab() } label: {
                            Image(systemName: "plus").font(.system(size: 10))
                        }.buttonStyle(.plain)

                        if template.tabs.count > 1 {
                            Button { moveTabUp() } label: {
                                Image(systemName: "chevron.up").font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedTabIndex <= 0)

                            Button { moveTabDown() } label: {
                                Image(systemName: "chevron.down").font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedTabIndex >= template.tabs.count - 1)

                            Spacer()

                            Button { removeTab() } label: {
                                Image(systemName: "minus").font(.system(size: 10))
                            }.buttonStyle(.plain)
                        } else {
                            Spacer()
                        }
                    }
                    .padding(6)
                }
                .frame(width: 180)

                Divider()

                // Right: selected tab detail
                tabDetailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Lifecycle commands
            commandsSection

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

            // Footer
            HStack {
                Button("Copy JSON") { copyJSON() }
                    .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 11))
                Spacer()
                Button("Done") { onSave(template); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Tab List Row

    private func tabListRow(_ tab: TemplateTab) -> some View {
        let index = template.tabs.firstIndex(where: { $0.id == tab.id }) ?? 0
        return HStack(spacing: 4) {
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

    @ViewBuilder
    private var tabDetailView: some View {
        let idx = selectedTabIndex
        if idx >= 0 && idx < template.tabs.count {
            let tab = template.tabs[idx]
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    field("Title") {
                        TextField("Tab title", text: $template.tabs[idx].title)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    field("Agent") {
                        Menu {
                            Button("None") { template.tabs[idx].agent = nil }
                            Divider()
                            ForEach(AgentType.builtIn, id: \.displayName) { agent in
                                Button(agent.displayName) { template.tabs[idx].agent = agent }
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

                    if tab.agent == nil {
                        field("Command") {
                            HStack {
                                TextField("e.g., make run", text: Binding(
                                    get: { template.tabs[idx].command ?? "" },
                                    set: { template.tabs[idx].command = $0.isEmpty ? nil : $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                                Toggle("Auto-run", isOn: $template.tabs[idx].autoRun)
                                    .toggleStyle(.checkbox)
                                    .font(.system(size: 10))
                            }
                        }
                    }

                    HStack(spacing: 16) {
                        field("Pin") {
                            Toggle("Pinned", isOn: $template.tabs[idx].isPinned)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 10))
                        }

                        field("Color") {
                            HStack(spacing: 3) {
                                Button { template.tabs[idx].colorName = nil } label: {
                                    Circle().strokeBorder(.secondary, lineWidth: 0.5).frame(width: 12, height: 12)
                                }.buttonStyle(.plain)
                                ForEach(["blue", "green", "orange", "red", "purple", "teal"], id: \.self) { c in
                                    Button { template.tabs[idx].colorName = c } label: {
                                        Circle().fill(TagDefinition.swiftUIColor(for: c)).frame(width: 12, height: 12)
                                            .overlay(Circle().strokeBorder(.white, lineWidth: tab.colorName == c ? 1.5 : 0))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        field("Icon") {
                            Menu {
                                Button("Default") { template.tabs[idx].iconOverride = nil }
                                Divider()
                                ForEach([
                                    ("terminal", "Terminal"), ("globe", "Web"), ("server.rack", "Server"),
                                    ("hammer", "Build"), ("testtube.2", "Test"), ("doc.text", "Docs"),
                                ], id: \.0) { icon, label in
                                    Button(label) { template.tabs[idx].iconOverride = icon }
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

                    field("Splits") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(tab.splits.enumerated()), id: \.element.id) { splitIdx, split in
                                splitRow(tabIndex: idx, splitIndex: splitIdx, split: split)
                            }
                            Button("Add Split") {
                                template.tabs[idx].splits.append(
                                    TemplateSplit(command: "", autoRun: true)
                                )
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.bordered).controlSize(.mini)
                        }
                    }
                }
                .padding(12)
            }
        } else {
            Text("Select a tab")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Split Row

    private func splitRow(tabIndex: Int, splitIndex: Int, split: TemplateSplit) -> some View {
        HStack(spacing: 6) {
            Button {
                template.tabs[tabIndex].splits[splitIndex].direction =
                    split.direction == .horizontal ? .vertical : .horizontal
            } label: {
                Image(systemName: split.direction == .horizontal ? "rectangle.split.1x2" : "rectangle.split.2x1")
                    .font(.system(size: 10))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(split.direction == .horizontal ? "Horizontal" : "Vertical")

            TextField("command", text: Binding(
                get: { template.tabs[tabIndex].splits[splitIndex].command ?? "" },
                set: { template.tabs[tabIndex].splits[splitIndex].command = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 10, design: .monospaced))

            TextField("subdir", text: Binding(
                get: { template.tabs[tabIndex].splits[splitIndex].subdirectory ?? "" },
                set: { template.tabs[tabIndex].splits[splitIndex].subdirectory = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 10, design: .monospaced))
            .frame(width: 80)

            Toggle("", isOn: $template.tabs[tabIndex].splits[splitIndex].autoRun)
                .toggleStyle(.checkbox)
                .help("Auto-run")

            Button {
                template.tabs[tabIndex].splits.remove(at: splitIndex)
            } label: {
                Image(systemName: "xmark").font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(4)
    }

    // MARK: - Lifecycle Commands

    private var commandsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { showingCommands.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: showingCommands ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7))
                    Text("Lifecycle Commands")
                        .font(.system(size: 9, weight: .medium))
                        .textCase(.uppercase)
                    if template.onCreateCommand != nil || template.onDestroyCommand != nil {
                        Circle().fill(.green).frame(width: 5, height: 5)
                    }
                    Spacer()
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)

            if showingCommands {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("On Create")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.tertiary)
                        MultilineTextView(text: Binding(
                            get: { template.onCreateCommand ?? "" },
                            set: { template.onCreateCommand = $0.isEmpty ? nil : $0 }
                        ), placeholder: "e.g. make install && yarn dev")
                        .frame(height: 60)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("On Destroy")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.tertiary)
                        MultilineTextView(text: Binding(
                            get: { template.onDestroyCommand ?? "" },
                            set: { template.onDestroyCommand = $0.isEmpty ? nil : $0 }
                        ), placeholder: "e.g. docker compose down")
                        .frame(height: 60)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func addTab() {
        let tab = TemplateTab(title: "New Tab")
        template.tabs.append(tab)
        selectedTabID = tab.id
    }

    private func removeTab() {
        let idx = selectedTabIndex
        guard idx < template.tabs.count else { return }
        template.tabs.remove(at: idx)
        if template.tabs.isEmpty {
            selectedTabID = nil
        } else {
            selectedTabID = template.tabs[min(idx, template.tabs.count - 1)].id
        }
    }

    private func moveTabUp() {
        let idx = selectedTabIndex
        guard idx > 0 else { return }
        template.tabs.swapAt(idx, idx - 1)
    }

    private func moveTabDown() {
        let idx = selectedTabIndex
        guard idx < template.tabs.count - 1 else { return }
        template.tabs.swapAt(idx, idx + 1)
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

    // MARK: - Helpers

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            content()
        }
    }
}

// MARK: - Multi-line text view with paste support

private struct MultilineTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont = .monospacedSystemFont(ofSize: 10, weight: .regular)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = font
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textColor = .labelColor
        textView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.3)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
