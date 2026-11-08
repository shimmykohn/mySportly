import SwiftUI
import WidgetKit

private struct WidgetChannel: Codable, Identifiable { var id: String; var name: String; var program: String? }
private struct WidgetSnapshot: Codable { var updatedAt: Date; var channels: [WidgetChannel]; var favorites: [String] }
private struct LineupEntry: TimelineEntry { var date: Date; var snapshot: WidgetSnapshot? }
private struct LineupProvider: TimelineProvider {
    func placeholder(in context: Context) -> LineupEntry { LineupEntry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (LineupEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LineupEntry>) -> Void) { completion(Timeline(entries: [entry()], policy: .after(Date.now.addingTimeInterval(1800)))) }
    private func entry() -> LineupEntry {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.iska.mysportly"), let data = try? Data(contentsOf: root.appending(path: "lineup.json")), let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return LineupEntry(date: .now, snapshot: nil) }
        return LineupEntry(date: .now, snapshot: snapshot)
    }
}
private struct LineupWidgetView: View {
    let entry: LineupEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your Channels", systemImage: "play.tv").font(.headline)
            if let snapshot = entry.snapshot, !snapshot.channels.isEmpty {
                let favorites = snapshot.channels.filter { snapshot.favorites.contains($0.id) }
                ForEach(Array((favorites.isEmpty ? snapshot.channels : favorites).prefix(family == .systemSmall ? 2 : (family == .systemMedium ? 3 : 6)))) { channel in
                    Link(destination: playURL(channel.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.name).font(.subheadline.bold()).lineLimit(1)
                            if let program = channel.program, entry.date.timeIntervalSince(snapshot.updatedAt) < 900 { Text(program).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer(minLength: 0)
                Link("Open Guide", destination: URL(string: "mysportly://guide")!).font(.caption)
            } else {
                Text("Connect a source and choose your favorite channels in mySportly.").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "mysportly://guide"))
    }
    private func playURL(_ id: String) -> URL { var url = URLComponents(); url.scheme = "mysportly"; url.host = "play"; url.queryItems = [URLQueryItem(name: "id", value: id)]; return url.url! }
}
@main struct mySportlyWidgets: WidgetBundle {
    var body: some Widget { LineupWidget() }
}
private struct LineupWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "mySportly.lineup", provider: LineupProvider()) { entry in LineupWidgetView(entry: entry) }
            .configurationDisplayName("Your TV Lineup")
            .description("Quick access to your favorite channels and TV guide.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
