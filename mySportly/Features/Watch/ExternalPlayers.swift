import SwiftUI

/// Apps to fall back on when an MKV or similar file won't play here. The link
/// carries the provider URL with its credentials to the app the user picks.
enum ExternalPlayer: String, CaseIterable, Identifiable {
    case infuse, vlc
    var id: Self { self }
    var name: String { self == .infuse ? "Infuse" : "VLC" }
    private var scheme: String { self == .infuse ? "infuse" : "vlc-x-callback" }
    var appStore: URL {
        URL(string: self == .infuse ? "https://apps.apple.com/app/id1136220934" : "https://apps.apple.com/app/id650377962")!
    }
    @MainActor var isInstalled: Bool { URL(string: "\(scheme)://").map(UIApplication.shared.canOpenURL) ?? false }
    func link(for media: URL) -> URL? {
        guard let encoded = media.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        let action = self == .infuse ? "play" : "stream"
        return URL(string: "\(scheme)://x-callback-url/\(action)?url=\(encoded)")
    }
}

/// "Open in Infuse / VLC" for a title that may not play here, or links to get them.
struct OpenElsewhere: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    let item: WatchProgress

    var body: some View {
        let installed = ExternalPlayer.allCases.filter(\.isInstalled)
        VStack(alignment: .leading, spacing: 10) {
            Text("If this \(item.container.uppercased()) file won’t play here, open it in another app. Your place there isn’t tracked.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if installed.isEmpty {
                    ForEach(ExternalPlayer.allCases) { app in
                        Button("Get \(app.name)", systemImage: "arrow.down.app") { openURL(app.appStore) }
                    }
                } else {
                    ForEach(installed) { app in
                        Button("Open in \(app.name)", systemImage: "arrow.up.forward.app") { open(in: app) }
                            .accessibilityIdentifier("open-in-\(app.rawValue)")
                    }
                }
            }
            .buttonStyle(.glass)
        }
    }

    private func open(in app: ExternalPlayer) {
        guard let media = store.externalMediaURL(item), let link = app.link(for: media) else {
            store.inform("Couldn’t open", "This title’s address isn’t available right now."); return
        }
        openURL(link)
    }
}
