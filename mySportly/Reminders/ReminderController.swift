import Foundation
import UserNotifications
import Observation

struct ProgramReminder: Identifiable, Hashable { var id: String; var title: String; var channelName: String; var fireDate: Date; var channelID: String? }
@MainActor @Observable final class ReminderController {
    private(set) var reminders: [ProgramReminder] = []
    private(set) var permission = UNAuthorizationStatus.notDetermined
    func reload() async {
        let center = UNUserNotificationCenter.current()
        permission = await center.notificationSettings().authorizationStatus
        reminders = await center.pendingNotificationRequests().compactMap { request in
            guard request.identifier.hasPrefix("program."), let trigger = request.trigger as? UNCalendarNotificationTrigger, let date = trigger.nextTriggerDate() else { return nil }
            return ProgramReminder(id: request.identifier, title: request.content.title, channelName: request.content.body, fireDate: date, channelID: request.content.userInfo["channelID"] as? String)
        }.sorted { $0.fireDate < $1.fireDate }
    }
    func schedule(program: GuideProgram, channel: Channel, minutesBefore: Int = 0) async throws {
        let center = UNUserNotificationCenter.current()
        let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard allowed else { throw ReminderFailure.denied }
        let fire = program.start.addingTimeInterval(-Double(minutesBefore * 60))
        guard fire > .now else { throw ReminderFailure.past }
        let content = UNMutableNotificationContent()
        content.title = program.title; content.body = channel.name; content.sound = .default
        content.userInfo = ["channelID": channel.id]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        try await center.add(UNNotificationRequest(identifier: "program.\(program.id)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        await reload()
    }
    func cancel(_ id: String) async { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id]); await reload() }
    func reschedule(_ reminder: ProgramReminder, date: Date) async throws {
        guard date > .now else { throw ReminderFailure.past }
        let content = UNMutableNotificationContent(); content.title = reminder.title; content.body = reminder.channelName; content.sound = .default
        if let channelID = reminder.channelID { content.userInfo = ["channelID": channelID] }
        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)); await reload()
    }
    enum ReminderFailure: Error, LocalizedError {
        case denied, past
        var errorDescription: String? { self == .denied ? "Allow notifications for mySportly in device Settings to receive reminders." : "Choose a reminder time in the future." }
    }
}
