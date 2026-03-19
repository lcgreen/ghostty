import Foundation

/// Launches AI agents in workspace terminals.
///
/// Agent-agnostic design: agents are opaque CLI processes.
/// We simply send the launch command as text input to the terminal surface.
/// Ghostty handles all terminal I/O, rendering, and process lifecycle.
enum AgentLauncher {

    /// Returns environment variables to inject into the terminal surface.
    /// These are passed via SurfaceConfiguration.environmentVariables.
    static func environmentVariables(for workspace: Workspace) -> [String: String] {
        var env: [String: String] = [
            "GHOSTSET_WORKSPACE_NAME": workspace.name,
            "GHOSTSET_WORKSPACE_PATH": workspace.worktreePath,
            "GHOSTSET_REPO_PATH": workspace.repoPath,
            "GHOSTSET_BRANCH": workspace.branch,
        ]

        if let agent = workspace.agent {
            env["GHOSTSET_AGENT"] = agent.launchCommand
        }

        return env
    }
}
