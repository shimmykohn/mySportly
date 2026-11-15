import Foundation

/// `mysportly://` links (notification taps, external links): play, guide,
/// search and refresh. Routes wait until the full catalog is ready.
enum AppRouteInbox {
    static func url(_ action: String, name: String, value: String) -> URL {
        var result = URLComponents(); result.scheme = "mysportly"; result.host = action
        result.queryItems = [URLQueryItem(name: name, value: value)]
        return result.url!
    }
    static func playURL(_ channelID: String) -> URL { url("play", name: "id", value: channelID) }
    static let notification = Notification.Name("mySportly.route")
    @MainActor static func queue(_ url: URL) { UserDefaults.standard.set(url.absoluteString, forKey: "pendingRoute"); NotificationCenter.default.post(name: notification, object: nil) }
    @MainActor static func consume(using store: AppStore) {
        guard store.catalogReady, store.routingReady, let text = UserDefaults.standard.string(forKey: "pendingRoute"), let url = URL(string: text) else { return }
        UserDefaults.standard.removeObject(forKey: "pendingRoute"); store.route(url)
    }
}
