import SwiftUI

/// Project creation mode.
enum ProjectMode: String, CaseIterable {
    case empty, clone

    var title: String {
        switch self {
        case .empty: return "Empty"
        case .clone: return "Clone"
        }
    }

    var subtitle: String {
        switch self {
        case .empty: return "New git repository from scratch"
        case .clone: return "Clone from a remote URL"
        }
    }

    var icon: String {
        switch self {
        case .empty: return "folder.badge.plus"
        case .clone: return "arrow.down.circle"
        }
    }
}

/// New Project sheet — the entry point for creating workspaces.
/// Supports Empty, Clone, and Template modes.
struct NewProjectSheet: View {
    @ObservedObject var manager: WorktreeManager
    let onCreated: (Workspace) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var mode: ProjectMode = .clone
    @State private var location = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ghostset/projects").path
    @State private var repoURL = ""
    @State private var repoName = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            content
            footer
        }
        .frame(width: 520, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Project")
                .font(.system(size: 20, weight: .bold))

            // Location
            VStack(alignment: .leading, spacing: 6) {
                Text("Location")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("", text: $location)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(8)
                        .background(fieldBackground)
                        .cornerRadius(8)

                    Button(action: browseLocation) {
                        Image(systemName: "folder")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(GhostsetButtonStyle())
                }
            }

            // Mode selector
            HStack(spacing: 10) {
                ForEach(ProjectMode.allCases, id: \.self) { m in
                    modeCard(m)
                }
            }

            // Mode-specific input
            modeInput
        }
        .padding(24)
    }

    // MARK: - Mode Cards

    private func modeCard(_ m: ProjectMode) -> some View {
        let isSelected = mode == m

        return Button(action: { withAnimation(.easeInOut(duration: 0.15)) { mode = m } }) {
            VStack(spacing: 8) {
                Image(systemName: m.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(m.title)
                    .font(.system(size: 12, weight: .semibold))

                Text(m.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                        lineWidth: 1
                    )
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mode Input

    @ViewBuilder
    private var modeInput: some View {
        switch mode {
        case .clone:
            VStack(alignment: .leading, spacing: 6) {
                Text("Repository URL")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("https:// or git@github.com:user/repo.git", text: $repoURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8)
                    .background(fieldBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                    )
            }

        case .empty:
            VStack(alignment: .leading, spacing: 6) {
                Text("Repository Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("my-project", text: $repoName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(8)
                    .background(fieldBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                    )
            }

        }

        if let error = errorMessage {
            Text(error)
                .font(.system(size: 11))
                .foregroundColor(.red)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()

            Button(action: createProject) {
                Text(mode == .clone ? "Clone" : "Create")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(!isValid || isCreating)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
    }

    // MARK: - Validation

    private var isValid: Bool {
        switch mode {
        case .clone: return !repoURL.isEmpty
        case .empty: return !repoName.isEmpty
        }
    }

    // MARK: - Actions

    private func createProject() {
        isCreating = true
        errorMessage = nil

        Task {
            do {
                let repoPath: String
                switch mode {
                case .clone:
                    repoPath = try await cloneRepo()
                case .empty:
                    repoPath = try await createEmptyRepo()
                }

                let workspace = try await manager.createWorkspace(
                    repo: repoPath,
                    name: "main",
                    baseBranch: "main"
                )
                dismiss()
                onCreated(workspace)
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }

    private func cloneRepo() async throws -> String {
        let name = repoURL.split(separator: "/").last?
            .replacingOccurrences(of: ".git", with: "") ?? "project"
        let dest = "\(location)/\(name)"
        let url = repoURL

        try FileManager.default.createDirectory(
            atPath: location, withIntermediateDirectories: true
        )

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["clone", url, dest]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        continuation.resume(throwing: NSError(
                            domain: "Ghostset", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to clone repository"]
                        ))
                        return
                    }
                    continuation.resume(returning: dest)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func createEmptyRepo() async throws -> String {
        let dest = "\(location)/\(repoName)"

        try FileManager.default.createDirectory(
            atPath: dest, withIntermediateDirectories: true
        )

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["init", dest]
                process.standardOutput = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: dest)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func browseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            location = url.path
        }
    }

    // MARK: - Helpers

    private var fieldBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.04)
    }
}

// MARK: - Ghostset Button Style

struct GhostsetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .background(Color.secondary.opacity(configuration.isPressed ? 0.15 : 0.1))
            .cornerRadius(8)
    }
}
