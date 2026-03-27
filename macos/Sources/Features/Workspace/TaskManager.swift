import Foundation
import SwiftUI

// MARK: - TaskStatus

enum TaskStatus: Equatable {
    case pending
    case running
    case completed
    case failed(String)
    case cancelled
}

// MARK: - WorkspaceTask

final class WorkspaceTask: Identifiable, ObservableObject {
    let id = UUID()
    let title: String
    let workspaceID: UUID?
    @Published var status: TaskStatus = .pending
    @Published var progress: Double? = nil
    let createdAt = Date()
    var swiftTask: Task<Void, Never>?

    init(title: String, workspaceID: UUID? = nil) {
        self.title = title
        self.workspaceID = workspaceID
    }
}

// MARK: - TaskManager

final class TaskManager: ObservableObject {
    @Published var tasks: [WorkspaceTask] = []
    @Published var taskHistory: [WorkspaceTask] = []
    private let maxHistory = 50

    // MARK: - Computed Properties

    var activeTasks: [WorkspaceTask] {
        tasks.filter { $0.status == .pending || $0.status == .running }
    }

    var recentTasks: [WorkspaceTask] {
        tasks.filter { task in
            switch task.status {
            case .completed, .failed, .cancelled: return true
            default: return false
            }
        }
    }

    var hasActiveTasks: Bool { !activeTasks.isEmpty }

    // MARK: - Enqueue

    /// Enqueue and immediately start a task.
    /// Operations on the same workspaceID are serialized (waits for previous to finish).
    @discardableResult
    @MainActor
    func enqueue(
        title: String,
        workspaceID: UUID? = nil,
        operation: @escaping () async throws -> Void
    ) -> WorkspaceTask {
        let task = WorkspaceTask(title: title, workspaceID: workspaceID)
        tasks.append(task)

        task.swiftTask = Task { @MainActor in
            // Wait for any earlier active task on the same workspace
            if let wsID = workspaceID {
                while self.tasks.contains(where: {
                    $0.workspaceID == wsID &&
                    $0.id != task.id &&
                    ($0.status == .pending || $0.status == .running) &&
                    $0.createdAt < task.createdAt
                }) {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    if Task.isCancelled {
                        task.status = .cancelled
                        return
                    }
                }
            }

            task.status = .running
            do {
                try await operation()
                if !Task.isCancelled {
                    task.status = .completed
                }
            } catch {
                if !Task.isCancelled {
                    task.status = .failed(error.localizedDescription)
                }
            }

            // Save to history
            self.taskHistory.insert(task, at: 0)
            if self.taskHistory.count > self.maxHistory {
                self.taskHistory = Array(self.taskHistory.prefix(self.maxHistory))
            }

            // Auto-remove completed/cancelled tasks after 5 seconds
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self.tasks.removeAll { t in
                    t.id == task.id && (t.status == .completed || t.status == .cancelled)
                }
            }
        }

        return task
    }

    // MARK: - Cancel

    @MainActor
    func cancel(taskID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        task.swiftTask?.cancel()
        task.status = .cancelled
    }

    // MARK: - Clear

    @MainActor
    func clearHistory() {
        taskHistory.removeAll()
    }

    @MainActor
    func clearCompleted() {
        tasks.removeAll { task in
            switch task.status {
            case .completed, .failed, .cancelled: return true
            default: return false
            }
        }
    }
}
