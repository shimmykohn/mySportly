import Foundation
import UserNotifications

/// Local notifications when a followed team's game starts. Only requests with
/// the `game.` prefix are owned here; each update replaces them all.
enum GameAlertScheduler {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func update(_ alerts: [(alert: GameAlert, channelID: String?, channelName: String?)]) async {
        let center = UNUserNotificationCenter.current()
        let owned = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("game.") }
        center.removePendingNotificationRequests(withIdentifiers: owned)
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        for item in alerts {
            let content = UNMutableNotificationContent()
            content.title = item.alert.title
            content.body = item.channelName.map { "Starting now on \($0)" } ?? "Starting now"
            content.sound = .default
            if let channelID = item.channelID { content.userInfo = ["channelID": channelID] }
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.alert.date)
            try? await center.add(UNNotificationRequest(identifier: item.alert.id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
        }
    }
}
