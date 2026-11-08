import Foundation
import WidgetKit

struct SharedChannel: Codable, Hashable, Identifiable, Sendable { var id: String; var name: String; var program: String? }
struct SharedLineup: Codable, Sendable { var updatedAt: Date; var channels: [SharedChannel]; var favorites: [String] }
enum WidgetBridge {
    static let group = "group.app.iska.mysportly"
    static var directory: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
    static func save(_ snapshot: SharedLineup) async {
        guard let directory else { return }
        do {
            try await catalogWork {
                let data = try JSONEncoder().encode(snapshot)
                try Task.checkCancellation()
                try data.write(to: directory.appending(path: "lineup.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
        catch { /* The main app remains usable if the widget entitlement is not provisioned. */ }
    }
    static func read() -> SharedLineup? {
        guard let directory, let data = try? Data(contentsOf: directory.appending(path: "lineup.json")) else { return nil }
        return try? JSONDecoder().decode(SharedLineup.self, from: data)
    }
    static func playURL(_ id: String) -> URL {
        var components = URLComponents(); components.scheme = "mysportly"; components.host = "play"; components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url!
    }
}

enum AppRouteInbox {
    static func url(_ action: String, name: String, value: String) -> URL {
        var result = URLComponents(); result.scheme = "mysportly"; result.host = action
        result.queryItems = [URLQueryItem(name: name, value: value)]
        return result.url!
    }
    static let notification = Notification.Name("mySportly.route")
    @MainActor static func queue(_ url: URL) { UserDefaults.standard.set(url.absoluteString, forKey: "pendingRoute"); NotificationCenter.default.post(name: notification, object: nil) }
    @MainActor static func consume(using store: AppStore) {
        guard !store.loading, store.routingReady, let text = UserDefaults.standard.string(forKey: "pendingRoute"), let url = URL(string: text) else { return }
        UserDefaults.standard.removeObject(forKey: "pendingRoute"); store.route(url)
    }
}
