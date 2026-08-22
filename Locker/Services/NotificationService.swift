import Foundation
import UserNotifications

/// Schedules the local notifications that keep work from being forgotten.
///
/// Every reschedule wipes and rebuilds Locker's notifications, which keeps the
/// system in sync with the database without tracking individual identifiers.
@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var scheduledCount = 0

    /// macOS keeps a limited number of pending local notifications; staying well
    /// under it means the nearest reminders always survive.
    private let maximumPending = 60
    private let prefix = "locker."

    private init() {}

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    struct Request {
        var id: String
        var title: String
        var body: String
        var fireAt: Date
    }

    func reschedule(_ requests: [Request]) async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: existing.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )

        let upcoming = requests
            .filter { $0.fireAt > Date() }
            .sorted { $0.fireAt < $1.fireAt }
            .prefix(maximumPending)

        for request in upcoming {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: request.fireAt
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let notification = UNNotificationRequest(
                identifier: prefix + request.id,
                content: content,
                trigger: trigger
            )
            try? await center.add(notification)
        }

        scheduledCount = upcoming.count
    }

    /// Fires a few seconds out so the student can confirm notifications work.
    func sendTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Locker reminders are on"
        content.body = "This is what a due-date reminder will look like."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: prefix + "test." + UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        scheduledCount = 0
    }
}
