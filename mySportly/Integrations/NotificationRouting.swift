import UIKit
import UserNotifications

final class NotificationRouting: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let channelID = response.notification.request.content.userInfo["channelID"] as? String else {
            completionHandler(); return
        }
        Task { @MainActor in
            AppRouteInbox.queue(WidgetBridge.playURL(channelID))
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
