import SwiftUI

/// Sheet presented when creating a new workspace.
/// User picks a repo, names the workspace, selects a base branch, and optionally picks an agent.
struct NewWorkspaceSheet: View {
    @ObservedObject var manager: WorktreeManager
    let onCreated: (Workspace) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var repoPath = ""
    @State private var workspaceName = ""
    @State private var baseBranch = "main"
    @State private var selectedAgent: AgentType? = .claude
    @State private var useAgent = true
    @State private var isCreating = false
    @State private var errorMessage: String?

    // Recently used repos (persisted separately in production)
    @State private var recentRepos: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            formContent
            Divider()
            sheetFooter
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            Text("New Workspace")
                .font(.headline)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    // MARK: - Form

    private var formContent: some View {
        Form {
            // Repository
            Section {
                HStack {
                    TextField("Repository path", text: $repoPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse") {
                        browseForRepo()
                    }
                }
            } header: {
                Text("Repository")
            }

            // Workspace name
            Section {
                TextField("e.g. add-auth, fix-bug-123", text: $workspaceName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: workspaceName) { _, newValue in
                        // Sanitize: lowercase, hyphens only
                        workspaceName = sanitizeName(newValue)
                    }
            } header: {
                Text("Workspace Name")
            } footer: {
                Text("Used as the branch name: ghostset/\(workspaceName.isEmpty ? "<name>" : workspaceName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Base branch
            Section {
                TextField("Branch to fork from", text: $baseBranch)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Base Branch")
            }

            // Agent selection
            Section {
                Toggle("Launch an agent", isOn: $useAgent)

                if useAgent {
                    Picker("Agent", selection: $selectedAgent) {
                        Text("None").tag(nil as AgentType?)
                        ForEach(AgentType.builtIn, id: \.self) { agent in
                            Label(agent.displayName, systemImage: agent.iconName)
                                .tag(agent as AgentType?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Agent")
            }

            // Error display
            if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var sheetFooter: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Create Workspace") {
                createWorkspace()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!isValid || isCreating)
        }
        .padding()
    }

    // MARK: - Validation

    private var isValid: Bool {
        !repoPath.isEmpty && !workspaceName.isEmpty && !baseBranch.isEmpty
    }

    // MARK: - Actions

    private func createWorkspace() {
        guard isValid else { return }
        isCreating = true
        errorMessage = nil

        Task {
            do {
                let workspace = try await manager.createWorkspace(
                    repo: repoPath,
                    name: workspaceName,
                    baseBranch: baseBranch,
                    agent: useAgent ? selectedAgent : nil
                )
                dismiss()
                onCreated(workspace)
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }

    private func browseForRepo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository"

        if panel.runModal() == .OK, let url = panel.url {
            repoPath = url.path
        }
    }

    private func sanitizeName(_ input: String) -> String {
        input
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}
