import SwiftUI

/// A tag definition with a name and associated color.
/// Stored in the tag registry (persisted to ~/.ghostset/state.json).
struct TagDefinition: Codable, Identifiable, Hashable {
    let name: String
    var colorName: String

    var id: String { name }

    var color: Color {
        Self.swiftUIColor(for: colorName)
    }

    // MARK: - Preset Tags

    static let presets: [TagDefinition] = [
        TagDefinition(name: "feature", colorName: "blue"),
        TagDefinition(name: "bugfix", colorName: "red"),
        TagDefinition(name: "refactor", colorName: "purple"),
        TagDefinition(name: "experiment", colorName: "orange"),
        TagDefinition(name: "review", colorName: "teal"),
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
}
