import Foundation
import Combine

// MARK: - WorkspaceProfile

/// A named group of workspaces that filters the sidebar to a focused context.
/// Membership is stored on the profile (not on the workspace), enabling many-to-many relationships.
/// Workspaces not in any profile appear in all views ("unassigned = global").
///
/// IMPORTANT: Equatable/Hashable use compiler-synthesized conformances (all fields).
/// Do NOT add id-only implementations — SwiftUI relies on full-field comparison to detect state changes.
struct WorkspaceProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var iconName: String
    var colorName: String
    var workspaceIDs: Set<UUID>
    var sortOrder: Int
    let createdAt: Date

    init(
        name: String,
        iconName: String = "folder",
        colorName: String = "blue",
        workspaceIDs: Set<UUID> = [],
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.colorName = colorName
        self.workspaceIDs = workspaceIDs
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    // Backward-compatible decoder — old persisted data won't have new fields
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        iconName = try c.decodeIfPresent(String.self, forKey: .iconName) ?? "folder"
        colorName = try c.decodeIfPresent(String.self, forKey: .colorName) ?? "blue"
        workspaceIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .workspaceIDs) ?? []
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

// MARK: - ProfileState

/// Top-level container persisted to ~/.ghostset/profiles.json
struct ProfileState: Codable {
    var version: Int = 1
    var profiles: [WorkspaceProfile] = []
    var activeProfileID: UUID? = nil
    var lastUpdated: Date = Date()
}

// MARK: - ProfilePersistence

/// Reads and writes ProfileState to ~/.ghostset/profiles.json.
/// Separate file from state.json to avoid write contention and allow independent versioning.
final class ProfilePersistence {

    private let path: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ghostset/profiles.json"
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func load() -> ProfileState {
        guard let data = FileManager.default.contents(atPath: path) else {
            return ProfileState()
        }
        do {
            return try decoder.decode(ProfileState.self, from: data)
        } catch {
            print("[ProfilePersistence] Warning: failed to decode profiles.json: \(error)")
            return ProfileState()
        }
    }

    func save(_ state: ProfileState) {
        do {
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true
            )
            var s = state
            s.lastUpdated = Date()
            let data = try encoder.encode(s)
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            print("[ProfilePersistence] Save failed: \(error)")
        }
    }
}

// MARK: - ProfileManager

/// Observable manager for workspace profiles.
/// Owned by WorktreeManager and injected into the sidebar via environment or direct reference.
final class ProfileManager: ObservableObject {

    @Published private(set) var profiles: [WorkspaceProfile]
    @Published private(set) var activeProfileID: UUID?

    private let persistence = ProfilePersistence()

    init() {
        let state = persistence.load()
        self.profiles = state.profiles.sorted { $0.sortOrder < $1.sortOrder }
        self.activeProfileID = state.activeProfileID
    }

    // MARK: - Active Profile

    var activeProfile: WorkspaceProfile? {
        guard let id = activeProfileID else { return nil }
        return profiles.first { $0.id == id }
    }

    func setActiveProfile(_ profileID: UUID?) {
        activeProfileID = profileID
        saveInBackground()
    }

    // MARK: - CRUD

    func createProfile(
        name: String,
        iconName: String = "folder",
        colorName: String = "blue"
    ) -> WorkspaceProfile {
        let sortOrder = (profiles.map(\.sortOrder).max() ?? -1) + 1
        let profile = WorkspaceProfile(
            name: name,
            iconName: iconName,
            colorName: colorName,
            sortOrder: sortOrder
        )
        profiles.append(profile)
        saveInBackground()
        return profile
    }

    func updateProfile(_ profile: WorkspaceProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        saveInBackground()
    }

    func deleteProfile(_ profile: WorkspaceProfile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id {
            activeProfileID = nil
        }
        saveInBackground()
    }

    // MARK: - Workspace Membership

    func assignWorkspace(id workspaceID: UUID, to profileID: UUID) {
        // Remove from all other profiles first (exclusive membership)
        profiles = profiles.map { profile in
            guard profile.id != profileID, profile.workspaceIDs.contains(workspaceID) else { return profile }
            var p = profile
            p.workspaceIDs.remove(workspaceID)
            return p
        }
        guard let idx = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        var updated = profiles[idx]
        updated.workspaceIDs.insert(workspaceID)
        profiles[idx] = updated
        saveInBackground()
    }

    func unassignWorkspace(id workspaceID: UUID, from profileID: UUID) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        var updated = profiles[idx]
        updated.workspaceIDs.remove(workspaceID)
        profiles[idx] = updated
        saveInBackground()
    }

    /// Called when a workspace is deleted — removes it from every profile that references it.
    func removeWorkspaceFromAllProfiles(id workspaceID: UUID) {
        var changed = false
        profiles = profiles.map { profile in
            guard profile.workspaceIDs.contains(workspaceID) else { return profile }
            var updated = profile
            updated.workspaceIDs.remove(workspaceID)
            changed = true
            return updated
        }
        if changed {
            saveInBackground()
        }
    }

    // MARK: - Filtering

    /// Returns the set of workspace IDs visible under the currently active profile.
    ///
    /// Rules:
    /// - If activeProfileID == nil (All Workspaces): returns all workspace IDs
    /// - If a profile is active: returns only that profile's members
    func filteredWorkspaceIDs(allWorkspaces: [Workspace]) -> Set<UUID> {
        guard let profile = activeProfile else {
            // "All Workspaces" — no filtering
            return Set(allWorkspaces.map(\.id))
        }

        return profile.workspaceIDs
    }

    // MARK: - Persistence

    private func saveInBackground() {
        let state = ProfileState(
            profiles: profiles,
            activeProfileID: activeProfileID
        )
        DispatchQueue.global(qos: .utility).async { [persistence, state] in
            persistence.save(state)
        }
    }
}
