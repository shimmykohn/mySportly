import SwiftUI

enum BrowseDestination: Hashable {
    case category(String)
    case league(SportsLibraryItem)
}

/// Sports, News, Movies, Kids, then each added league, then common sports.
/// Tiles are plain buttons: several links in one List row would all fire.
struct BrowseTiles: View {
    @Environment(AppStore.self) private var store
    @Binding var query: String
    @Binding var destination: BrowseDestination?

    private static let categories: [(String, String, Color)] = [
        ("Sports", "sportscourt.fill", .green), ("News", "newspaper.fill", .blue),
        ("Movies", "film.fill", .purple), ("Kids", "figure.and.child.holdinghands", .orange),
    ]
    private static let sports: [(String, String)] = [
        ("Basketball", "basketball.fill"), ("Football", "football.fill"), ("Soccer", "soccerball"),
        ("Baseball", "baseball.fill"), ("Hockey", "hockey.puck.fill"),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Self.categories, id: \.0) { title, symbol, tint in
                Button { destination = .category(title) } label: { Tile(title: title, tint: tint) { Image(systemName: symbol) } }
                    .accessibilityIdentifier("browse-\(title)")
            }
            ForEach(store.addedLeagues) { league in
                Button { destination = .league(league) } label: {
                    Tile(title: league.name, tint: .indigo) { SportsLogo(url: store.logo(for: league), size: 30) }
                }
                .accessibilityIdentifier("browse-\(league.name)")
            }
            ForEach(Self.sports, id: \.0) { title, symbol in
                Button { query = title } label: { Tile(title: title, tint: .teal) { Image(systemName: symbol) } }
                    .accessibilityIdentifier("browse-\(title)")
            }
        }
        .buttonStyle(.plain)
    }
}

private struct Tile<Icon: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder let icon: Icon
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            icon.font(.title2).foregroundStyle(.white)
            Text(title).font(.headline).foregroundStyle(.white).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .bottomLeading)
        .padding(14)
        .background(tint.gradient, in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
    }
}

/// Lineup channels in one category.
struct BrowseCategoryView: View {
    @Environment(AppStore.self) private var store
    let category: String
    @State private var channels: [Channel]?
    @State private var limit = 100

    var body: some View {
        List {
            if let channels {
                if channels.isEmpty { ContentUnavailableView("No \(category) Channels", systemImage: "tv") }
                ForEach(channels.prefix(limit)) { PlayableChannelRow(channel: $0) }
                if channels.count > limit { Button("Show More") { limit += 100 } }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(category)
        .task(id: store.queryRevision) {
            guard let directory = store.directory else { return }
            var request = ChannelBrowseRequest()
            request.category = category; request.audience = store.audience
            request.collapseVariants = true; request.excludeInactive = true; request.ranked = true
            channels = (try? await catalogWork { try directory.browse(request) }) ?? []
        }
    }
}
