import SwiftUI

/// Shown when no workspace is selected.
/// Provides a quick-start guide and new workspace button.
struct WelcomeView: View {
    var onNewWorkspace: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo / Title
            VStack(spacing: 8) {
                Image(systemName: "rectangle.stack.badge.play")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                Text("Ghostset")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("GPU-accelerated parallel agent workspaces")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Quick start
            VStack(alignment: .leading, spacing: 16) {
                featureRow(
                    icon: "plus.rectangle.on.rectangle",
                    title: "Create a Workspace",
                    description: "Each workspace gets its own git worktree and terminal"
                )
                featureRow(
                    icon: "brain.head.profile",
                    title: "Launch an Agent",
                    description: "Run Claude, Codex, Gemini, or any CLI agent"
                )
                featureRow(
                    icon: "rectangle.split.3x1",
                    title: "Work in Parallel",
                    description: "Multiple agents working on different branches simultaneously"
                )
                featureRow(
                    icon: "arrow.triangle.merge",
                    title: "Review & Merge",
                    description: "See diffs, commit changes, and create PRs from each workspace"
                )
            }
            .frame(maxWidth: 400)

            // New workspace button
            if let action = onNewWorkspace {
                Button(action: action) {
                    Label("New Workspace", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            // Keyboard shortcut hint
            Text("Cmd+Shift+N to create a workspace")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
