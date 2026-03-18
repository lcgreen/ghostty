import Foundation

/// Launches AI agents in workspace terminals.
///
/// Agent-agnostic design: agents are opaque CLI processes.
/// We simply send the launch command as text input to the terminal surface.
/// Ghostty handles all terminal I/O, rendering, and process lifecycle.
enum AgentLauncher {

    /// Builds the initial input string that will be sent to the terminal
    /// when the workspace surface is created.
    ///
    /// In the Ghostty fork, use this as `SurfaceConfiguration.initialInput`:
    /// ```swift
    /// var config = SurfaceConfiguration()
    /// config.initialInput = AgentLauncher.initialInput(for: agent, workspace: ws)
    /// ```
    static func initialInput(for agent: AgentType, workspace: Workspace) -> String {
        var commands: [String] = []

        // Set workspace environment variables in the shell
        commands.append("export GHOSTSET_WORKSPACE_NAME='\(workspace.name)'")
        commands.append("export GHOSTSET_REPO_PATH='\(workspace.repoPath)'")

        // Launch the agent
        commands.append(agent.launchCommand)

        return commands.joined(separator: "\n") + "\n"
    }

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
