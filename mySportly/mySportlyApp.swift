import SwiftUI
import CoreData
import Combine

@main struct mySportlyApp: App {
    @UIApplicationDelegateAdaptor(NotificationRouting.self) private var notificationRouting
    @State private var store = AppStore(inMemory: ProcessInfo.processInfo.arguments.contains("--demo"), registerBackground: true)
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .preferredColorScheme(colorScheme)
                .task { await store.load() }
                .onOpenURL { AppRouteInbox.queue($0); AppRouteInbox.consume(using: store) }
                .onChange(of: phase) { _, phase in
                    if phase == .background {
                        store.organizationEnteredBackground()
                        store.scheduleSourceRefresh()
                    }
                    if phase == .active {
                        store.clock = .now
                        Task {
                            guard store.catalogReady else { return }
                            store.matchSportsGames()
                            let revision = store.personal.revision
                            await store.personal.refreshCloudStatus()
                            if store.personal.revision != revision { store.rebuild() }
                            await store.restoreMissingSources()
                            await store.reminders.reload()
                            AppRouteInbox.consume(using: store)
                            await store.refreshDueSources()
                        }
                    }
                }
                .onChange(of: store.personal.revision) { _, _ in store.updateIntentCatalog() }
                .onChange(of: store.refreshSchedule) { _, _ in store.scheduleSourceRefresh() }
                .onChange(of: store.sources) { _, _ in store.scheduleSourceRefresh() }
                .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in if phase == .active { store.clock = date } }
                .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: DispatchQueue.main)) { _ in
                    if store.personal.reload(), store.catalogReady {
                        store.rebuild()
                        Task { await store.restoreMissingSources() }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification).receive(on: DispatchQueue.main)) { notification in
                    if let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event { store.personal.handleCloudEvent(event) }
                }
                .onReceive(NotificationCenter.default.publisher(for: AppRouteInbox.notification)) { _ in AppRouteInbox.consume(using: store) }
        }
    }
    private var colorScheme: ColorScheme? {
        switch store.personal.value("preferences.appearance", default: "System") { case "Light": .light; case "Dark": .dark; default: nil }
    }
}
