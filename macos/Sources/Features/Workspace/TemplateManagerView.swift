import SwiftUI

/// Sheet for managing workspace templates — view, edit, delete, create.
struct TemplateManagerView: View {
    @ObservedObject var manager: WorktreeManager
    @Environment(\.dismiss) private var dismiss

    @State private var editingTemplate: WorkspaceTemplate?
    @State private var showingNew = false

    @State private var formName = ""
    @State private var formAgent: AgentType? = .claude
    @State private var formBranch = "main"
    @State private var formTags: Set<String> = []
    @State private var formCategory: TemplateCategory = .aiAgents

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            templateList
            Divider()
            footer
        }
        .frame(width: 420, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Templates").font(.system(size: 14, weight: .semibold))
            Spacer()
            Button { showingNew.toggle() } label: {
                Image(systemName: "plus").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    // MARK: - Template List

    private var templateList: some View {
        Group {
            if manager.templates.isEmpty && !showingNew {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(TemplateCategory.allCases, id: \.self) { cat in
                            let items = manager.templates.filter { $0.category == cat }
                            if !items.isEmpty { categorySection(cat, items: items) }
                        }
                        if showingNew { templateForm(editing: nil) }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.doc").font(.title2).foregroundStyle(.tertiary)
            Text("No custom templates").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("Templates let you quickly create workspaces\nwith pre-configured agents, tags, and branches.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Create Template") { showingNew = true }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
    }

    // MARK: - Category Section

    private func categorySection(_ category: TemplateCategory, items: [WorkspaceTemplate]) -> some View {
        Section {
            ForEach(items) { template in
                if editingTemplate?.id == template.id {
                    templateForm(editing: template)
                } else {
                    templateRow(template)
                }
                Divider().opacity(0.2).padding(.horizontal, 12)
            }
            .onMove { source, dest in moveTemplates(in: category, from: source, to: dest) }
        } header: {
            HStack(spacing: 5) {
                Image(systemName: category.iconName).font(.system(size: 9))
                Text(category.rawValue).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Template Row

    private func templateRow(_ template: WorkspaceTemplate) -> some View {
        HStack(spacing: 10) {
            if let agent = template.agent {
                Image(systemName: agent.iconName).font(.system(size: 11))
                    .foregroundColor(AgentColors.color(for: agent)).frame(width: 16)
            } else {
                Image(systemName: "terminal").font(.system(size: 11))
                    .foregroundStyle(.secondary).frame(width: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(.system(size: 12, weight: .medium))
                HStack(spacing: 4) {
                    if let agent = template.agent {
                        Text(agent.displayName).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Text(template.baseBranch)
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                    ForEach(template.tags, id: \.self) { tag in
                        let def = manager.tagDefinition(for: tag)
                        Text(tag).font(.system(size: 8, weight: .medium))
                            .foregroundColor(def.color.opacity(0.8))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(def.color.opacity(0.12)).clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Button { manager.saveTemplate(template.duplicated()) } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Duplicate")

            Button { manager.removeTemplate(template) } label: {
                Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { beginEditing(template) }
    }

    // MARK: - Template Form (New / Edit)

    private func templateForm(editing: WorkspaceTemplate?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(editing != nil ? "Edit Template" : "New Template")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)

            TextField("Template name", text: $formName)
                .textFieldStyle(.roundedBorder).font(.system(size: 12))

            HStack(spacing: 8) {
                agentMenu
                TextField("base branch", text: $formBranch)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced)).frame(width: 100)
                categoryMenu
            }

            tagToggles

            HStack {
                Spacer()
                Button("Cancel") { cancelForm() }
                    .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 11))
                Button("Save") { saveForm(original: editing) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(formName.isEmpty)
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.03))
        .onAppear { if let t = editing { populateForm(t) } }
    }

    private var agentMenu: some View {
        Menu {
            ForEach(AgentType.builtIn, id: \.displayName) { agent in
                Button { formAgent = agent } label: {
                    Label(agent.displayName, systemImage: agent.iconName)
                }
            }
            Divider()
            Button { formAgent = nil } label: { Label("None", systemImage: "terminal") }
        } label: {
            menuLabel(icon: formAgent?.iconName ?? "terminal", text: formAgent?.displayName ?? "None")
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var categoryMenu: some View {
        Menu {
            ForEach(TemplateCategory.allCases, id: \.self) { cat in
                Button { formCategory = cat } label: {
                    Label(cat.rawValue, systemImage: cat.iconName)
                }
            }
        } label: {
            menuLabel(icon: formCategory.iconName, text: formCategory.rawValue)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func menuLabel(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 10))
            Image(systemName: "chevron.down").font(.system(size: 7))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08)).cornerRadius(4)
    }

    private var tagToggles: some View {
        HStack(spacing: 3) {
            ForEach(manager.tagDefinitions) { def in
                let on = formTags.contains(def.name)
                Button {
                    if on { formTags.remove(def.name) } else { formTags.insert(def.name) }
                } label: {
                    Text(def.name).font(.system(size: 9))
                        .foregroundColor(on ? def.color : .secondary.opacity(0.5))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(on ? def.color.opacity(0.15) : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(manager.templates.count) template\(manager.templates.count == 1 ? "" : "s")")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            Spacer()
            Button("Export All") { exportTemplates() }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 11))
            Button("Import") { importTemplates() }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 11))
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: - Actions

    private func beginEditing(_ template: WorkspaceTemplate) {
        editingTemplate = template
        populateForm(template)
    }

    private func populateForm(_ template: WorkspaceTemplate) {
        formName = template.name
        formAgent = template.agent
        formBranch = template.baseBranch
        formTags = Set(template.tags)
        formCategory = template.category
    }

    private func saveForm(original: WorkspaceTemplate?) {
        let saved = WorkspaceTemplate(
            name: formName, baseBranch: formBranch, agent: formAgent,
            tags: Array(formTags), category: formCategory
        )
        if let old = original { manager.removeTemplate(old) }
        manager.saveTemplate(saved)
        cancelForm()
    }

    private func cancelForm() {
        showingNew = false
        editingTemplate = nil
        formName = ""
        formAgent = .claude
        formBranch = "main"
        formTags = []
        formCategory = .aiAgents
    }

    private func moveTemplates(in category: TemplateCategory, from source: IndexSet, to dest: Int) {
        var catItems = manager.templates.filter { $0.category == category }
        catItems.move(fromOffsets: source, toOffset: dest)
        let others = manager.templates.filter { $0.category != category }
        manager.replaceAllTemplates(others + catItems)
    }

    // MARK: - Export / Import

    private func exportTemplates() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ghostset-templates.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            try enc.encode(manager.templates).write(to: url)
        } catch {
            print("[TemplateManagerView] Export failed: \(error)")
        }
    }

    private func importTemplates() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let imported = try dec.decode([WorkspaceTemplate].self, from: Data(contentsOf: url))
            for template in imported { manager.saveTemplate(template) }
        } catch {
            print("[TemplateManagerView] Import failed: \(error)")
        }
    }
}
