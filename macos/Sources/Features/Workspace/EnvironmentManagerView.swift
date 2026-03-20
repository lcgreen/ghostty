import SwiftUI

/// Standalone sheet for managing environment profiles — Dev, Staging, Prod, custom.
struct EnvironmentManagerView: View {
    @ObservedObject var manager: WorktreeManager
    @Environment(\.dismiss) private var dismiss

    @State private var editingProfile: EnvironmentProfile?
    @State private var showingNew = false
    @State private var newName = ""
    @State private var newColor = "green"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            profileList
            Divider()
            footer
        }
        .frame(width: 440, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
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

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Environments")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if manager.environmentProfiles.isEmpty {
                Button("Add Presets") {
                    for preset in EnvironmentProfile.presets {
                        manager.upsertEnvironmentProfile(preset)
                    }
                    manager.setActiveProfile(manager.environmentProfiles.first?.id)
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button { showingNew.toggle() } label: {
                Image(systemName: "plus").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    // MARK: - Profile List

    private var profileList: some View {
        Group {
            if manager.environmentProfiles.isEmpty && !showingNew {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(manager.environmentProfiles) { profile in
                            profileRow(profile)
                            Divider().opacity(0.15).padding(.horizontal, 16)
                        }
                        if showingNew {
                            newProfileForm
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.title2).foregroundStyle(.tertiary)
            Text("No environment profiles")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text("Profiles store environment variables for different contexts\nlike Development, Staging, and Production.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("Add Presets") {
                    for preset in EnvironmentProfile.presets {
                        manager.upsertEnvironmentProfile(preset)
                    }
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Button("Create Custom") { showingNew = true }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
    }

    // MARK: - Profile Row

    private func profileRow(_ profile: EnvironmentProfile) -> some View {
        let isActive = profile.id == manager.activeProfileID
        let color = TagDefinition.swiftUIColor(for: profile.colorName)

        return HStack(spacing: 10) {
            // Color dot + active indicator
            ZStack {
                Circle().fill(color).frame(width: 10, height: 10)
                if isActive {
                    Circle().strokeBorder(Color.white, lineWidth: 1.5).frame(width: 14, height: 14)
                }
            }
            .frame(width: 16)

            // Name + var count
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    if isActive {
                        Text("active")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(color.opacity(0.15))
                            .cornerRadius(3)
                    }
                }

                // Variable preview
                let sortedVars = profile.variables.sorted { $0.key < $1.key }
                if sortedVars.isEmpty {
                    Text("No variables")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                } else {
                    Text(sortedVars.prefix(3).map { "\($0.key)=\($0.value)" }.joined(separator: "  "))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Var count badge
            Text("\(profile.variables.count)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(4)

            // Actions
            Button {
                manager.setActiveProfile(isActive ? nil : profile.id)
            } label: {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundColor(isActive ? color : .secondary)
            }
            .buttonStyle(.plain)
            .help(isActive ? "Deactivate" : "Activate")

            Button { editingProfile = profile } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button { manager.removeEnvironmentProfile(profile) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isActive ? color.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            manager.setActiveProfile(isActive ? nil : profile.id)
        }
    }

    // MARK: - New Profile Form

    private var newProfileForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Profile")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Profile name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                // Color dots
                HStack(spacing: 3) {
                    ForEach(["green", "orange", "red", "blue", "purple", "teal"], id: \.self) { c in
                        Circle()
                            .fill(TagDefinition.swiftUIColor(for: c))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: newColor == c ? 1.5 : 0))
                            .onTapGesture { newColor = c }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    showingNew = false
                    newName = ""
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Create") {
                    let profile = EnvironmentProfile(
                        name: newName.trimmingCharacters(in: .whitespaces),
                        variables: [:],
                        colorName: newColor
                    )
                    manager.upsertEnvironmentProfile(profile)
                    showingNew = false
                    newName = ""
                    // Open editor immediately
                    editingProfile = profile
                }
                .font(.system(size: 11))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(manager.environmentProfiles.count) profile\(manager.environmentProfiles.count == 1 ? "" : "s")")
                .font(.system(size: 10)).foregroundStyle(.tertiary)

            if let active = manager.activeProfile {
                HStack(spacing: 3) {
                    Circle().fill(TagDefinition.swiftUIColor(for: active.colorName)).frame(width: 5, height: 5)
                    Text(active.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}
