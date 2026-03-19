import SwiftUI

/// Quick workspace creation prompt — appears inline or as a popover.
/// "What do you want to do?" + agent picker + workspace name + branch.
struct QuickWorkspacePrompt: View {
    @ObservedObject var manager: WorktreeManager
    let onCreated: (Workspace, AgentType?) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var workspaceName = ""
    @State private var branchName = ""
    @State private var taskDescription = ""
    @State private var selectedAgent: AgentType = .claude
    @State private var selectedRepo: String?
    @State private var baseBranch = "main"
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Name + branch row
            nameRow

            // Task description
            taskInput

            // Bottom bar: repo, branch, hint
            bottomBar

            // Error display
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }

    // MARK: - Name Row

    private var nameRow: some View {
        HStack(spacing: 0) {
            TextField("Workspace name (optional)", text: $workspaceName)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .onChange(of: workspaceName) { newValue in
                    workspaceName = sanitize(newValue)
                    if branchName.isEmpty || branchName == sanitize(String(workspaceName.dropLast())) {
                        branchName = workspaceName
                    }
                }

            Spacer()

            Text(branchName.isEmpty ? "branch-name" : branchName)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 12)
        }
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Task Input

    private var taskInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("What do you want to do?", text: $taskDescription, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(3...6)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            HStack(spacing: 6) {
                agentPicker
                Spacer()

                // + button (for attachments/context — future)
                Button(action: {}) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                // Submit
                Button(action: createWorkspace) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(isValid ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!isValid || isCreating)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Agent Picker

    private var agentPicker: some View {
        Menu {
            ForEach(AgentType.builtIn, id: \.displayName) { agent in
                Button {
                    selectedAgent = agent
                } label: {
                    Label(agent.displayName, systemImage: agent.iconName)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selectedAgent.iconName)
                    .font(.system(size: 10))
                Text(selectedAgent.displayName.capitalized)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            // Repo picker
            if let repos = availableRepos, !repos.isEmpty {
                Menu {
                    ForEach(repos, id: \.self) { repo in
                        Button(repoDisplayName(repo)) {
                            selectedRepo = repo
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.green)
                        Text(selectedRepo.map(repoDisplayName) ?? "Select repo")
                            .font(.system(size: 11))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Base branch
            Menu {
                ForEach(["main", "master", "develop", "staging"], id: \.self) { branch in
                    Button(branch) { baseBranch = branch }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                    Text(baseBranch)
                        .font(.system(size: 11))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                }
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Text("\u{2318}\u{21A9} to create")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Validation

    private var isValid: Bool {
        selectedRepo != nil && !taskDescription.isEmpty
    }

    // MARK: - Available Repos

    private var availableRepos: [String]? {
        let repos = manager.workspaces.map(\.repoPath)
        return Array(Set(repos)).sorted()
    }

    // MARK: - Actions

    private func createWorkspace() {
        guard let repo = selectedRepo, isValid else { return }
        isCreating = true

        let name = workspaceName.isEmpty
            ? sanitize(String(taskDescription.prefix(30)))
            : workspaceName

        Task {
            do {
                let workspace = try await manager.createWorkspace(
                    repo: repo,
                    name: name,
                    baseBranch: baseBranch,
                    agent: selectedAgent
                )
                onCreated(workspace, selectedAgent)
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }

    // MARK: - Helpers

    private func sanitize(_ input: String) -> String {
        input.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private func repoDisplayName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
