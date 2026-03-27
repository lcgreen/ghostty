import SwiftUI

/// Compact dropdown that replaces the static "Workspaces" label in the sidebar header.
/// Lets users switch between "All Workspaces" and named profiles, and open the manager sheet.
struct ProfileSwitcher: View {
    @ObservedObject var profileManager: ProfileManager
    var onManageProfiles: () -> Void

    var body: some View {
        Menu {
            allWorkspacesItem
            if !profileManager.profiles.isEmpty {
                Divider()
                ForEach(profileManager.profiles) { profile in
                    profileItem(profile)
                }
            }
            Divider()
            Button {
                onManageProfiles()
            } label: {
                Label("Manage Profiles...", systemImage: "gear")
            }
        } label: {
            menuLabel
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Menu Items

    private var allWorkspacesItem: some View {
        Button {
            profileManager.setActiveProfile(nil)
        } label: {
            HStack {
                Label("All Workspaces", systemImage: "tray.2")
                if profileManager.activeProfileID == nil {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func profileItem(_ profile: WorkspaceProfile) -> some View {
        Button {
            profileManager.setActiveProfile(profile.id)
        } label: {
            HStack {
                Label(profile.name, systemImage: profile.iconName)
                if profileManager.activeProfileID == profile.id {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    // MARK: - Label

    private var menuLabel: some View {
        HStack(spacing: 3) {
            if let profile = profileManager.activeProfile {
                Image(systemName: profile.iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(colorValue(for: profile.colorName))
                Text(profile.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text("Workspaces")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
    }

    // MARK: - Helpers

    private func colorValue(for colorName: String) -> Color {
        switch colorName {
        case "blue":   return .blue
        case "green":  return .green
        case "orange": return .orange
        case "red":    return .red
        case "purple": return .purple
        case "yellow": return .yellow
        case "pink":   return .pink
        case "gray":   return .gray
        default:       return .accentColor
        }
    }
}
