import SwiftUI

// MARK: - TaskStatusBar

/// Compact sidebar footer bar showing active and recently completed tasks.
/// Click to open full task history popover.
struct TaskStatusBar: View {
    @ObservedObject var taskManager: TaskManager
    @State private var showingHistory = false

    private let maxVisible = 3

    private var visibleTasks: [WorkspaceTask] {
        let all = taskManager.activeTasks + taskManager.recentTasks
        return Array(all.prefix(maxVisible))
    }

    private var overflowCount: Int {
        let all = taskManager.activeTasks + taskManager.recentTasks
        return max(0, all.count - maxVisible)
    }

    var body: some View {
        let all = taskManager.activeTasks + taskManager.recentTasks
        if all.isEmpty && taskManager.taskHistory.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 2) {
                // Active/recent tasks
                ForEach(visibleTasks) { task in
                    TaskRowView(task: task) {
                        taskManager.cancel(taskID: task.id)
                    }
                }
                if overflowCount > 0 {
                    Text("+\(overflowCount) more")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                }

                // History button (when no active tasks but history exists)
                if all.isEmpty && !taskManager.taskHistory.isEmpty {
                    Button {
                        showingHistory = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 9))
                            Text("Task History")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else if !all.isEmpty {
                    // Clickable "View history" link
                    Button {
                        showingHistory = true
                    } label: {
                        Text("View history")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Rectangle())
            .popover(isPresented: $showingHistory) {
                TaskHistoryView(taskManager: taskManager)
            }
        }
    }
}

// MARK: - TaskRowView

private struct TaskRowView: View {
    @ObservedObject var task: WorkspaceTask
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            statusIcon
            Text(task.title)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            trailingContent
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .pending:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
        case .running:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        switch task.status {
        case .pending, .running:
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        case .completed:
            Text(task.createdAt, style: .relative)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .font(.system(size: 9))
                .foregroundStyle(.red)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 80)
        case .cancelled:
            EmptyView()
        }
    }
}

// MARK: - TaskHistoryView

private struct TaskHistoryView: View {
    @ObservedObject var taskManager: TaskManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Task History")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if !taskManager.taskHistory.isEmpty {
                    Button("Clear") {
                        taskManager.clearHistory()
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(10)

            Divider()

            if taskManager.taskHistory.isEmpty && taskManager.activeTasks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No tasks")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Active tasks first
                        ForEach(taskManager.activeTasks) { task in
                            TaskHistoryRow(task: task)
                            Divider().opacity(0.3)
                        }

                        // History
                        ForEach(taskManager.taskHistory) { task in
                            TaskHistoryRow(task: task)
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
        .frame(width: 300, height: 280)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TaskHistoryRow: View {
    @ObservedObject var task: WorkspaceTask

    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            Group {
                switch task.status {
                case .pending, .running:
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                case .cancelled:
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 11))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(task.createdAt, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)

                    if case .failed(let msg) = task.status {
                        Text("— \(msg)")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}
