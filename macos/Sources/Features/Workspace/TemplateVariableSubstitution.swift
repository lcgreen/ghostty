import Foundation

enum TemplateVariableSubstitution {
    /// Replace {{name}} tokens with values from dictionary.
    /// Use \{{ in template text to produce a literal {{ in output.
    static func substitute(_ input: String, variables: [String: String]) -> String {
        var result = input
        for (name, value) in variables {
            result = result.replacingOccurrences(of: "{{\(name)}}", with: value)
        }
        result = result.replacingOccurrences(of: "\\{{", with: "{{")
        return result
    }

    /// Return a new template with all text fields substituted.
    static func substituteTemplate(_ template: WorkspaceTemplate, values: [String: String]) -> WorkspaceTemplate {
        guard !values.isEmpty else { return template }
        var t = template
        t.onCreateCommand = t.onCreateCommand.map { substitute($0, variables: values) }
        t.onDestroyCommand = t.onDestroyCommand.map { substitute($0, variables: values) }
        t.setupCommand = t.setupCommand.map { substitute($0, variables: values) }
        t.tabs = t.tabs.map { tab in
            var tab = tab
            tab.command = tab.command.map { substitute($0, variables: values) }
            tab.splits = tab.splits.map { split in
                var split = split
                split.command = split.command.map { substitute($0, variables: values) }
                split.subdirectory = split.subdirectory.map { substitute($0, variables: values) }
                return split
            }
            tab.layout = tab.layout.map { substitutePane($0, variables: values) }
            return tab
        }
        return t
    }

    private static func substitutePane(_ pane: TemplatePane, variables: [String: String]) -> TemplatePane {
        switch pane {
        case .terminal(var leaf):
            leaf.command = leaf.command.map { substitute($0, variables: variables) }
            leaf.subdirectory = leaf.subdirectory.map { substitute($0, variables: variables) }
            return .terminal(leaf)
        case .split(var split):
            split.first = substitutePane(split.first, variables: variables)
            split.second = substitutePane(split.second, variables: variables)
            return .split(split)
        }
    }
}
