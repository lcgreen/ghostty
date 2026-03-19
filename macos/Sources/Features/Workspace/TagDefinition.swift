import SwiftUI

/// A tag definition with a name and associated color.
/// Stored in the tag registry (persisted to ~/.ghostset/state.json).
struct TagDefinition: Codable, Identifiable, Hashable {
    let name: String
    var colorName: String
    var iconName: String?
    var parentTag: String?

    var id: String { name }

    var color: Color {
        Self.swiftUIColor(for: colorName)
    }

    /// Display name showing hierarchy (e.g., "frontend/react").
    var displayName: String {
        if let parent = parentTag {
            return "\(parent)/\(name)"
        }
        return name
    }

    init(name: String, colorName: String, iconName: String? = nil, parentTag: String? = nil) {
        self.name = name
        self.colorName = colorName
        self.iconName = iconName
        self.parentTag = parentTag
    }

    // Backward-compatible decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        colorName = try container.decode(String.self, forKey: .colorName)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        parentTag = try container.decodeIfPresent(String.self, forKey: .parentTag)
    }

    // MARK: - Preset Tags

    static let presets: [TagDefinition] = [
        TagDefinition(name: "feature", colorName: "blue", iconName: "star"),
        TagDefinition(name: "bugfix", colorName: "red", iconName: "ladybug"),
        TagDefinition(name: "refactor", colorName: "purple", iconName: "arrow.triangle.2.circlepath"),
        TagDefinition(name: "experiment", colorName: "orange", iconName: "flask"),
        TagDefinition(name: "review", colorName: "teal", iconName: "eye"),
    ]

    // MARK: - Available Colors

    static let availableColors: [(name: String, label: String)] = [
        ("blue", "Blue"),
        ("indigo", "Indigo"),
        ("purple", "Purple"),
        ("pink", "Pink"),
        ("red", "Red"),
        ("orange", "Orange"),
        ("yellow", "Yellow"),
        ("green", "Green"),
        ("teal", "Teal"),
        ("mint", "Mint"),
    ]

    static func swiftUIColor(for name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "teal": return .teal
        case "mint": return .mint
        default: return .secondary
        }
    }

    // MARK: - Auto-Tag Keywords

    /// Maps keywords found in workspace names/descriptions to tag names.
    static let autoTagKeywords: [String: String] = [
        "fix": "bugfix",
        "bug": "bugfix",
        "hotfix": "bugfix",
        "patch": "bugfix",
        "feat": "feature",
        "feature": "feature",
        "add": "feature",
        "implement": "feature",
        "refactor": "refactor",
        "cleanup": "refactor",
        "clean": "refactor",
        "reorganize": "refactor",
        "experiment": "experiment",
        "spike": "experiment",
        "try": "experiment",
        "proto": "experiment",
        "review": "review",
        "pr": "review",
    ]

    /// Infer tags from a workspace name or task description.
    static func inferTags(from text: String) -> [String] {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        var matched = Set<String>()
        for word in words {
            if let tag = autoTagKeywords[word] {
                matched.insert(tag)
            }
        }
        return Array(matched).sorted()
    }

    /// Detect language tags from repo contents.
    static func detectLanguageTags(repoPath: String) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: repoPath) else { return [] }
        var tags: [String] = []

        let fileSet = Set(contents)
        if fileSet.contains("package.json") || fileSet.contains("tsconfig.json") {
            tags.append("javascript")
        }
        if fileSet.contains("requirements.txt") || fileSet.contains("pyproject.toml") || fileSet.contains("setup.py") {
            tags.append("python")
        }
        if fileSet.contains("go.mod") {
            tags.append("go")
        }
        if fileSet.contains("Cargo.toml") {
            tags.append("rust")
        }
        if fileSet.contains("build.zig") {
            tags.append("zig")
        }
        if fileSet.contains("Package.swift") {
            tags.append("swift")
        }
        return tags
    }

    /// Count how many workspaces use this tag.
    static func usageCount(for tagName: String, in workspaces: [Workspace]) -> Int {
        workspaces.filter { $0.tags.contains(tagName) }.count
    }

    /// Pick the next unused color from the available palette.
    static func nextUnusedColor(usedColors: Set<String>) -> String {
        for colorOption in availableColors {
            if !usedColors.contains(colorOption.name) {
                return colorOption.name
            }
        }
        return availableColors.first?.name ?? "blue"
    }
}
