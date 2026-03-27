import SwiftUI

/// Sheet for managing workspace profiles — create, edit, assign workspaces, delete.
struct ProfileManagerView: View {
    @ObservedObject var manager: WorktreeManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProfileID: UUID?
    @State private var profileToDelete: WorkspaceProfile?

    // MARK: - Available Icons / Colors

    private let availableIcons = [
        "folder", "briefcase", "person", "building.2",
        "laptopcomputer", "house", "globe", "star",
        "heart", "wrench", "book", "hammer"
    ]

    private let availableColors = [
        "blue", "green", "orange", "red", "purple",
        "teal", "indigo", "pink", "yellow", "mint"
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                profileList
                    .frame(minWidth: 140, idealWidth: 160, maxWidth: 200)
                profileDetail
                    .frame(minWidth: 280)
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(
            "Delete Profile?",
            isPresented: .init(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let p = profileToDelete {
                    manager.profileManager.deleteProfile(p)
                    if selectedProfileID == p.id { selectedProfileID = nil }
                }
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) { profileToDelete = nil }
        } message: {
            if let p = profileToDelete { Text("Delete '\(p.name)'? Workspaces will not be affected.") }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Profiles").font(.system(size: 14, weight: .semibold))
            Spacer()
            Button {
                let profile = manager.profileManager.createProfile(name: "New Profile")
                selectedProfileID = profile.id
            } label: {
                Image(systemName: "plus").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    // MARK: - Profile List (left panel)

    private var profileList: some View {
        VStack(spacing: 0) {
            if manager.profileManager.profiles.isEmpty {
                emptyListState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(manager.profileManager.profiles) { profile in
                            profileRow(profile)
                            Divider().opacity(0.2).padding(.horizontal, 8)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            listControls
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var emptyListState: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.2").font(.title3).foregroundStyle(.tertiary)
            Text("No profiles").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    private func profileRow(_ profile: WorkspaceProfile) -> some View {
        let isSelected = selectedProfileID == profile.id
        return HStack(spacing: 6) {
            Image(systemName: profile.iconName)
                .font(.system(size: 10))
                .foregroundColor(colorValue(for: profile.colorName))
                .frame(width: 14)
            Text(profile.name)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedProfileID = profile.id }
    }

    private var listControls: some View {
        HStack(spacing: 0) {
            Button {
                let profile = manager.profileManager.createProfile(name: "New Profile")
                selectedProfileID = profile.id
            } label: {
                Image(systemName: "plus").font(.system(size: 11))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)

            Button {
                if let id = selectedProfileID,
                   let profile = manager.profileManager.profiles.first(where: { $0.id == id }) {
                    profileToDelete = profile
                }
            } label: {
                Image(systemName: "minus").font(.system(size: 11))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .disabled(selectedProfileID == nil)

            Spacer()
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(Color(nsColor: .separatorColor).opacity(0.1))
    }

    // MARK: - Profile Detail (right panel)

    @ViewBuilder
    private var profileDetail: some View {
        if let id = selectedProfileID,
           let index = manager.profileManager.profiles.firstIndex(where: { $0.id == id }) {
            ProfileDetailEditor(
                profileManager: manager.profileManager,
                profileID: id,
                workspaces: manager.workspaces,
                availableIcons: availableIcons,
                availableColors: availableColors,
                onDelete: { profile in profileToDelete = profile },
                colorValue: colorValue
            )
        } else {
            noSelectionPlaceholder
        }
    }

    private var noSelectionPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.badge.plus").font(.title2).foregroundStyle(.tertiary)
            Text("Select a profile to edit")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text("Or click + to create a new profile.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            let count = manager.profileManager.profiles.count
            Text("\(count) profile\(count == 1 ? "" : "s")")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: - Color Helper

    private func colorValue(for name: String) -> Color {
        switch name {
        case "blue":   return .blue
        case "green":  return .green
        case "orange": return .orange
        case "red":    return .red
        case "purple": return .purple
        case "teal":   return .teal
        case "indigo": return .indigo
        case "pink":   return .pink
        case "yellow": return Color.yellow
        case "mint":   return Color.mint
        default:       return .blue
        }
    }
}

// MARK: - ProfileDetailEditor

/// Extracted to avoid complex bindings with index-based mutation.
private struct ProfileDetailEditor: View {
    @ObservedObject var profileManager: ProfileManager
    let profileID: UUID
    let workspaces: [Workspace]
    let availableIcons: [String]
    let availableColors: [String]
    let onDelete: (WorkspaceProfile) -> Void
    let colorValue: (String) -> Color

    private var profile: WorkspaceProfile {
        profileManager.profiles.first(where: { $0.id == profileID }) ?? WorkspaceProfile(name: "")
    }

    @State private var name: String
    @State private var iconName: String
    @State private var colorName: String

    init(
        profileManager: ProfileManager,
        profileID: UUID,
        workspaces: [Workspace],
        availableIcons: [String],
        availableColors: [String],
        onDelete: @escaping (WorkspaceProfile) -> Void,
        colorValue: @escaping (String) -> Color
    ) {
        self.profileManager = profileManager
        self.profileID = profileID
        self.workspaces = workspaces
        self.availableIcons = availableIcons
        self.availableColors = availableColors
        self.onDelete = onDelete
        self.colorValue = colorValue
        let p = profileManager.profiles.first(where: { $0.id == profileID }) ?? WorkspaceProfile(name: "")
        _name = State(initialValue: p.name)
        _iconName = State(initialValue: p.iconName)
        _colorName = State(initialValue: p.colorName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                nameSection
                iconSection
                colorSection
                workspaceSection
                Divider()
                deleteSection
            }
            .padding(16)
        }
        .id(profile.id) // Reset state when profile changes
        .onChange(of: profile) { updated in
            name = updated.name
            iconName = updated.iconName
            colorName = updated.colorName
        }
    }

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Name").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField("Profile name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit { commitName() }
                .onChange(of: name) { _ in commitName() }
        }
    }

    private func commitName() {
        guard !name.isEmpty else { return }
        var updated = profile
        updated.name = name
        updated.iconName = iconName
        updated.colorName = colorName
        profileManager.updateProfile(updated)
    }

    // MARK: - Icon

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Icon").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32)), count: 6), spacing: 4) {
                ForEach(availableIcons, id: \.self) { icon in
                    let isSelected = iconName == icon
                    Button {
                        iconName = icon
                        saveChanges()
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 13))
                            .frame(width: 28, height: 28)
                            .background(isSelected ? colorValue(colorName).opacity(0.2) : Color.clear)
                            .foregroundColor(isSelected ? colorValue(colorName) : .secondary)
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(isSelected ? colorValue(colorName) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Color

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Color").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(availableColors, id: \.self) { color in
                    let isSelected = colorName == color
                    Button {
                        colorName = color
                        saveChanges()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(colorValue(color))
                                .frame(width: 20, height: 20)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Workspace Assignment

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workspaces").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if workspaces.isEmpty {
                Text("No workspaces yet.").font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 2) {
                    ForEach(workspaces) { workspace in
                        workspaceToggleRow(workspace)
                    }
                }
            }
        }
    }

    private func workspaceToggleRow(_ workspace: Workspace) -> some View {
        let isAssigned = profile.workspaceIDs.contains(workspace.id)
        return Button {
            if isAssigned {
                profileManager.unassignWorkspace(id: workspace.id, from: profileID)
            } else {
                profileManager.assignWorkspace(id: workspace.id, to: profileID)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isAssigned ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundColor(isAssigned ? colorValue(colorName) : .secondary)
                Text(workspace.name).font(.system(size: 12))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    // MARK: - Delete

    private var deleteSection: some View {
        HStack {
            Button(role: .destructive) {
                onDelete(profile)
            } label: {
                Label("Delete Profile", systemImage: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Save

    private func saveChanges() {
        var updated = profile
        updated.name = name.isEmpty ? profile.name : name
        updated.iconName = iconName
        updated.colorName = colorName
        profileManager.updateProfile(updated)
    }
}
