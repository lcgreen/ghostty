import SwiftUI

/// Per-workspace settings popover — global environment profiles, commands, shell, working directory.
struct WorkspaceSettingsPopover: View {
    @ObservedObject var manager: WorktreeManager
    let workspace: Workspace

    // Profile editor
    @State private var editingProfile: EnvironmentProfile?
    @State private var showingNewProfile = false
    @State private var newProfileName = ""
    @State private var newProfileColor = "blue"

    // Commands & settings
    @State private var setupCommand = ""
    @State private var teardownCommand = ""
    @State private var selectedShell = "Default"
    @State private var workingDirectory = ""
    @State private var showRunConfirm = false
    @State private var commandOutput: String?

    private static let shellOptions = ["Default", "/bin/zsh", "/bin/bash", "/usr/local/bin/fish", "/usr/bin/env nushell"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Workspace Settings")
                    .font(.system(size: 12, weight: .semibold))

                Divider().opacity(0.3)
                profileSwitcher
                Divider().opacity(0.3)
                commandSection(title: "Setup Command", text: $setupCommand, runnable: true)
                commandSection(title: "Teardown Command", text: $teardownCommand, runnable: false)
                Divider().opacity(0.3)
                shellSection
                workingDirectorySection
                Divider().opacity(0.3)
                infoSection
            }
            .padding(12)
        }
        .frame(width: 320, height: 480)
        .onAppear { loadSettings() }
        .alert("Run setup command?", isPresented: $showRunConfirm) {
            Button("Run") { runSetupCommand() }
            Button("Cancel", role: .cancel) {}
        } message: { Text(setupCommand) }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorSheet(
                profile: profile,
                onSave: { updated in
                    manager.upsertEnvironmentProfile(updated)
                    editingProfile = nil
                },
                onCancel: { editingProfile = nil }
            )
        }
    }

    // MARK: - Profile Switcher (global)

    private var profileSwitcher: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionHeader("Environment")
                Spacer()
                Button { showingNewProfile = true } label: {
                    Image(systemName: "plus").font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if manager.environmentProfiles.isEmpty && !showingNewProfile {
                HStack(spacing: 6) {
                    Text("No profiles")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Add Presets") {
                        for preset in EnvironmentProfile.presets {
                            manager.upsertEnvironmentProfile(preset)
                        }
                        manager.setActiveProfile(manager.environmentProfiles.first?.id)
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            } else {
                // Profile pills
                FlowLayout(spacing: 4) {
                    ForEach(manager.environmentProfiles) { profile in
                        profilePill(profile)
                    }
                }

                // Active profile detail
                if let active = manager.activeProfile {
                    activeProfileDetail(active)
                }
            }

            if showingNewProfile {
                newProfileForm
            }
        }
    }

    private func profilePill(_ profile: EnvironmentProfile) -> some View {
        let isActive = profile.id == manager.activeProfileID
        let color = TagDefinition.swiftUIColor(for: profile.colorName)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                manager.setActiveProfile(isActive ? nil : profile.id)
            }
        } label: {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(profile.name)
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                Text("\(profile.variables.count)")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            .foregroundColor(isActive ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? color.opacity(0.15) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isActive ? color.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit") { editingProfile = profile }
            Button("Duplicate") {
                let copy = EnvironmentProfile(
                    name: "\(profile.name) Copy",
                    variables: profile.variables,
                    colorName: profile.colorName
                )
                manager.upsertEnvironmentProfile(copy)
            }
            Divider()
            Button("Delete", role: .destructive) {
                manager.removeEnvironmentProfile(profile)
            }
        }
    }

    private func activeProfileDetail(_ profile: EnvironmentProfile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                let color = TagDefinition.swiftUIColor(for: profile.colorName)
                Circle().fill(color).frame(width: 5, height: 5)
                Text(profile.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("active")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.12))
                    .cornerRadius(3)
                Spacer()
                Button("Edit") { editingProfile = profile }
                    .font(.system(size: 9))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            let sortedVars = profile.variables.sorted { $0.key < $1.key }
            ForEach(sortedVars, id: \.key) { key, value in
                HStack(spacing: 4) {
                    Text(key)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("=")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                    Text(value)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(5)
    }

    // MARK: - New Profile Form

    private var newProfileForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New Profile")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                TextField("Profile name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))

                HStack(spacing: 3) {
                    ForEach(["green", "orange", "red", "blue", "purple", "teal"], id: \.self) { c in
                        Circle()
                            .fill(TagDefinition.swiftUIColor(for: c))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle().strokeBorder(Color.white, lineWidth: newProfileColor == c ? 1.5 : 0)
                            )
                            .onTapGesture { newProfileColor = c }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    showingNewProfile = false
                    newProfileName = ""
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Create") {
                    let profile = EnvironmentProfile(
                        name: newProfileName,
                        variables: [:],
                        colorName: newProfileColor
                    )
                    manager.upsertEnvironmentProfile(profile)
                    manager.setActiveProfile(profile.id)
                    showingNewProfile = false
                    newProfileName = ""
                    editingProfile = profile
                }
                .font(.system(size: 10))
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(5)
    }

    // MARK: - Commands

    private func commandSection(title: String, text: Binding<String>, runnable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(title)
            HStack(spacing: 4) {
                TextField("e.g., npm install", text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(6)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(4)
                    .onSubmit { saveCommands() }
                if runnable {
                    Button { showRunConfirm = true } label: {
                        Image(systemName: "play.fill").font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .disabled(text.wrappedValue.isEmpty)
                }
            }
            if runnable, let output = commandOutput {
                Text(output)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(4)
            }
        }
    }

    // MARK: - Shell & Working Dir

    private var shellSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Shell")
            Picker("", selection: $selectedShell) {
                ForEach(Self.shellOptions, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).font(.system(size: 10))
            .onChange(of: selectedShell) { _ in saveShell() }
        }
    }

    private var workingDirectorySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Working Directory")
            TextField("Subdirectory (optional)", text: $workingDirectory)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .padding(6)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(4)
                .onSubmit { saveWorkingDirectory() }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Path: \(workspace.worktreePath)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.middle)
            Text("Branch: \(workspace.branch)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary).textCase(.uppercase)
    }

    private func runSetupCommand() {
        let cmd = setupCommand, dir = workspace.worktreePath
        commandOutput = "Running..."
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", cmd]
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            let pipe = Pipe()
            process.standardOutput = pipe; process.standardError = pipe
            do {
                try process.run(); process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8) ?? "(no output)"
                DispatchQueue.main.async { commandOutput = result }
            } catch {
                DispatchQueue.main.async { commandOutput = "Error: \(error.localizedDescription)" }
            }
        }
    }

    // MARK: - Persistence (per-repo config for commands/shell/cwd)

    private func loadSettings() {
        let config = loadRepoConfig()
        setupCommand = config?.setupCommand ?? ""
        teardownCommand = config?.teardownCommand ?? ""
        selectedShell = config?.shell ?? "Default"
        workingDirectory = config?.workingDirectory ?? ""
    }

    private func saveCommands() {
        var config = loadRepoConfig() ?? WorkspaceConfig()
        config.setupCommand = setupCommand.isEmpty ? nil : setupCommand
        config.teardownCommand = teardownCommand.isEmpty ? nil : teardownCommand
        saveRepoConfig(config)
    }

    private func saveShell() {
        var config = loadRepoConfig() ?? WorkspaceConfig()
        config.shell = selectedShell == "Default" ? nil : selectedShell
        saveRepoConfig(config)
    }

    private func saveWorkingDirectory() {
        var config = loadRepoConfig() ?? WorkspaceConfig()
        config.workingDirectory = workingDirectory.isEmpty ? nil : workingDirectory
        saveRepoConfig(config)
    }

    private func loadRepoConfig() -> WorkspaceConfig? {
        let path = "\(workspace.repoPath)/.ghostset/config.json"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(WorkspaceConfig.self, from: data)
    }

    private func saveRepoConfig(_ config: WorkspaceConfig) {
        let dir = "\(workspace.repoPath)/.ghostset"
        let path = "\(dir)/config.json"
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: URL(fileURLWithPath: path))
        } catch {
            print("[WorkspaceSettings] Failed to save config: \(error)")
        }
    }
}

// MARK: - Profile Editor Sheet

struct ProfileEditorSheet: View {
    let profile: EnvironmentProfile
    let onSave: (EnvironmentProfile) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var colorName: String
    @State private var vars: [(key: String, value: String)]
    @State private var newKey = ""
    @State private var newValue = ""

    private static let quickVars: [(String, String)] = [
        ("NODE_ENV", "development"), ("DEBUG", "*"), ("LOG_LEVEL", "debug"),
        ("PORT", "3000"), ("DATABASE_URL", "postgres://localhost:5432/mydb"),
        ("RUST_LOG", "debug"), ("FLASK_ENV", "development"), ("RAILS_ENV", "development"),
        ("API_URL", "http://localhost:8080"), ("AWS_REGION", "us-east-1"),
    ]

    init(profile: EnvironmentProfile, onSave: @escaping (EnvironmentProfile) -> Void, onCancel: @escaping () -> Void) {
        self.profile = profile
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: profile.name)
        _colorName = State(initialValue: profile.colorName)
        _vars = State(initialValue: profile.variables.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(TagDefinition.swiftUIColor(for: colorName))
                    .frame(width: 8, height: 8)
                TextField("Profile name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(vars.count) vars")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)

            // Color picker
            HStack(spacing: 4) {
                ForEach(["green", "orange", "red", "blue", "purple", "teal", "indigo", "pink"], id: \.self) { c in
                    Circle()
                        .fill(TagDefinition.swiftUIColor(for: c))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: colorName == c ? 2 : 0))
                        .shadow(color: colorName == c ? TagDefinition.swiftUIColor(for: c).opacity(0.4) : .clear, radius: 2)
                        .onTapGesture { colorName = c }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Variables
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(vars.enumerated()), id: \.offset) { idx, _ in
                        HStack(spacing: 6) {
                            TextField("KEY", text: varBinding(idx, \.key))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .textFieldStyle(.plain)
                                .frame(width: 120)
                            Text("=").font(.system(size: 11)).foregroundStyle(.tertiary)
                            TextField("value", text: varBinding(idx, \.value))
                                .font(.system(size: 11, design: .monospaced))
                                .textFieldStyle(.plain)
                            Button { vars.remove(at: idx) } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        if idx < vars.count - 1 {
                            Divider().opacity(0.15).padding(.horizontal, 12)
                        }
                    }

                    // Add new
                    HStack(spacing: 6) {
                        TextField("NEW_KEY", text: $newKey)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.plain).frame(width: 120)
                        Text("=").font(.system(size: 11)).foregroundStyle(.tertiary)
                        TextField("value", text: $newValue)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.plain)
                            .onSubmit { addVar() }
                        Button { addVar() } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12)).foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.primary.opacity(0.02))
                }
            }

            Divider()

            // Footer
            HStack {
                Menu {
                    ForEach(Self.quickVars, id: \.0) { key, value in
                        Button("\(key)=\(value)") { addIfMissing(key, value) }
                    }
                } label: {
                    Label("Quick Add", systemImage: "plus.circle").font(.system(size: 10))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 90)

                Spacer()

                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Button("Save") {
                    var updated = profile
                    updated.name = name
                    updated.colorName = colorName
                    updated.variables = Dictionary(uniqueKeysWithValues: vars.map { ($0.key, $0.value) })
                    onSave(updated)
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 400, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func addVar() {
        let key = newKey.trimmingCharacters(in: .whitespaces).uppercased()
        guard !key.isEmpty else { return }
        vars.append((key: key, value: newValue))
        newKey = ""; newValue = ""
    }

    private func addIfMissing(_ key: String, _ value: String) {
        guard !vars.contains(where: { $0.key == key }) else { return }
        vars.append((key: key, value: value))
    }

    private func varBinding(_ idx: Int, _ kp: WritableKeyPath<(key: String, value: String), String>) -> Binding<String> {
        Binding(
            get: { idx < vars.count ? vars[idx][keyPath: kp] : "" },
            set: { if idx < vars.count { vars[idx][keyPath: kp] = $0 } }
        )
    }
}
