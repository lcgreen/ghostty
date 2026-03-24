import SwiftUI

/// Sheet that prompts the user to fill in template variable values before applying.
struct TemplateVariablePrompt: View {
    let variables: [TemplateVariable]
    let onApply: ([String: String]) -> Void
    let onCancel: () -> Void

    @State private var values: [UUID: String] = [:]

    init(variables: [TemplateVariable], onApply: @escaping ([String: String]) -> Void, onCancel: @escaping () -> Void) {
        self.variables = variables
        self.onApply = onApply
        self.onCancel = onCancel
        // Seed with default values
        var initial: [UUID: String] = [:]
        for v in variables { initial[v.id] = v.defaultValue }
        self._values = State(initialValue: initial)
    }

    private var canApply: Bool {
        variables.allSatisfy { v in
            !v.required || !(values[v.id] ?? "").isEmpty
        }
    }

    private func resolvedValues() -> [String: String] {
        var result: [String: String] = [:]
        for v in variables {
            result[v.name] = values[v.id] ?? v.defaultValue
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Template Variables")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(variables) { variable in
                        variableField(variable)
                    }
                }
                .padding(16)
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") { onApply(resolvedValues()) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canApply)
            }
            .padding(12)
        }
        .frame(width: 400)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func variableField(_ variable: TemplateVariable) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(variable.name.isEmpty ? "(unnamed)" : variable.name)
                    .font(.system(size: 11, weight: .medium))
                if variable.required {
                    Text("required")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(3)
                }
            }
            TextField(variable.defaultValue.isEmpty ? "Value" : variable.defaultValue,
                      text: Binding(
                          get: { values[variable.id] ?? variable.defaultValue },
                          set: { values[variable.id] = $0 }
                      ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            if !variable.description.isEmpty {
                Text(variable.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
