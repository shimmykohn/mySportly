import SwiftUI

enum BrowseDestination: Hashable {
    case category(String)
    case league(SportsLibraryItem)
}

/// Sports, News, Movies, Kids, then each added league, then common sports:
/// short Liquid Glass buttons, icon and label, straight on the background.
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
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            Button { store.selectedTab = .watch } label: {
                Tile(title: "Movies & TV") { Image(systemName: "play.rectangle.on.rectangle.fill").foregroundStyle(.indigo) }
            }
            .accessibilityIdentifier("browse-watch")
            ForEach(Self.categories, id: \.0) { title, symbol, tint in
                Button { destination = .category(title) } label: { Tile(title: title) { Image(systemName: symbol).foregroundStyle(tint) } }
                    .accessibilityIdentifier("browse-\(title)")
            }
            ForEach(store.addedLeagues) { league in
                Button { destination = .league(league) } label: { Tile(title: league.name) { SportsLogo(url: store.logo(for: league), size: 22) } }
                    .accessibilityIdentifier("browse-\(league.name)")
            }
            ForEach(Self.sports, id: \.0) { title, symbol in
                Button { query = title } label: { Tile(title: title) { Image(systemName: symbol).foregroundStyle(.teal) } }
                    .accessibilityIdentifier("browse-\(title)")
            }
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }
}

private struct Tile<Icon: View>: View {
    let title: String
    @ViewBuilder let icon: Icon
    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 24)
            Text(title).foregroundStyle(.primary).lineLimit(1)
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
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
                ForEach(store.collapseFamilies(Array(channels.prefix(limit))) { $0 }) { entry in
                    switch entry {
                    case .single(let channel): PlayableChannelRow(channel: channel)
                    case .family(let name, let members): ChannelFamilyRow(name: name, channels: members)
                    }
                }
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
