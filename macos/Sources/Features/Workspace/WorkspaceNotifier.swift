import Foundation
import UserNotifications
import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
    category: "workspace-notifier"
)

/// Monitors workspace activity and sends macOS notifications.
final class WorkspaceNotifier: ObservableObject {

    // MARK: - Types

    /// Per-workspace activity tracking.
    struct ActivityState {
        var lastOutputTime: Date?
        var wasActive: Bool = false
        var notifiedIdle: Bool = false
    }

    /// Notification event categories.
    enum NotificationCategory: String {
        case agentFinished = "agent_finished"
        case errorDetected = "error_detected"
        case buildComplete = "build_complete"
        case general = "general"

        var sound: UNNotificationSound {
            switch self {
            case .errorDetected: return .defaultCritical
            default: return .default
            }
        }
    }

    /// A logged notification entry.
    struct NotificationEntry: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let category: NotificationCategory
        let workspaceID: UUID
        let timestamp: Date
    }

    // MARK: - Published State

    @Published var unreadWorkspaces: Set<UUID> = []
    @Published private(set) var notificationHistory: [NotificationEntry] = []

    // MARK: - Configuration

    /// Configurable idle threshold in seconds (default 10).
    var idleThreshold: TimeInterval {
        get { UserDefaults.standard.double(forKey: "ghostset.idleThreshold").clamped(to: 5...300, default: 10) }
        set { UserDefaults.standard.set(newValue, forKey: "ghostset.idleThreshold") }
    }

    /// Error patterns to detect in terminal output.
    private static let errorPatterns: [String] = [
        "error:", "Error:", "ERROR:", "fatal:", "Fatal:",
        "panic:", "PANIC:", "exception:", "Exception:",
        "FAILED", "segfault", "Segmentation fault",
    ]

    // MARK: - Private State

    private var activityStates: [UUID: ActivityState] = [:]
    private var selectedWorkspaceID: UUID?
    private var timer: Timer?
    private let maxHistoryEntries = 50

    init() {
        requestPermission()
        registerCategories()
    }

    // MARK: - Permission & Categories

    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                logger.warning("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    private func registerCategories() {
        let switchAction = UNNotificationAction(
            identifier: "SWITCH_WORKSPACE",
            title: "Switch to Workspace",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "WORKSPACE_EVENT",
            actions: [switchAction],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Activity Tracking

    /// Call when terminal output is detected for a workspace.
    func recordActivity(workspaceID: UUID, output: String? = nil) {
        var state = activityStates[workspaceID] ?? ActivityState()
        state.lastOutputTime = Date()
        state.wasActive = true
        state.notifiedIdle = false
        activityStates[workspaceID] = state

        // Mark as unread if not currently selected
        if workspaceID != selectedWorkspaceID {
            unreadWorkspaces.insert(workspaceID)
        }

        // Check for error patterns in output
        if let output, workspaceID != selectedWorkspaceID {
            detectErrors(in: output, workspaceID: workspaceID)
        }
    }

    /// Call when user selects a workspace — clears unread badge.
    func markRead(workspaceID: UUID) {
        selectedWorkspaceID = workspaceID
        unreadWorkspaces.remove(workspaceID)
    }

    /// Check for idle workspaces and send notifications.
    func checkForIdleAgents(workspaces: [Workspace]) {
        let now = Date()
        let threshold = idleThreshold

        for ws in workspaces {
            guard ws.agent != nil,
                  var state = activityStates[ws.id],
                  state.wasActive,
                  !state.notifiedIdle,
                  let lastOutput = state.lastOutputTime,
                  now.timeIntervalSince(lastOutput) > threshold
            else { continue }

            state.notifiedIdle = true
            state.wasActive = false
            activityStates[ws.id] = state

            if ws.id != selectedWorkspaceID {
                sendNotification(
                    title: ws.name,
                    body: "\(ws.agent?.displayName ?? "Agent") appears to have finished",
                    category: .agentFinished,
                    workspaceID: ws.id
                )
                unreadWorkspaces.insert(ws.id)
            }
        }
    }

    // MARK: - Error Detection

    private func detectErrors(in output: String, workspaceID: UUID) {
        for pattern in Self.errorPatterns {
            if output.contains(pattern) {
                sendNotification(
                    title: "Error Detected",
                    body: "Terminal output contains: \(pattern)",
                    category: .errorDetected,
                    workspaceID: workspaceID
                )
                break
            }
        }
    }

    // MARK: - Start/Stop Monitoring

    func startMonitoring(workspaces: [Workspace]) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkForIdleAgents(workspaces: workspaces)
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Clear History

    func clearHistory() {
        notificationHistory.removeAll()
    }

    // MARK: - Send Notification

    private func sendNotification(title: String, body: String, category: NotificationCategory, workspaceID: UUID) {
        // Log to history
        let entry = NotificationEntry(
            title: title, body: body, category: category,
            workspaceID: workspaceID, timestamp: Date()
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.notificationHistory.insert(entry, at: 0)
            if self.notificationHistory.count > self.maxHistoryEntries {
                self.notificationHistory = Array(self.notificationHistory.prefix(self.maxHistoryEntries))
            }
        }

        // Send macOS notification
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = category.sound
        content.categoryIdentifier = "WORKSPACE_EVENT"
        content.userInfo = [
            "workspaceID": workspaceID.uuidString,
            "category": category.rawValue,
        ]

        let request = UNNotificationRequest(
            identifier: "ghostset-\(workspaceID.uuidString)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.warning("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Clamped Double

private extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        let value = self
        if value == 0 { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
