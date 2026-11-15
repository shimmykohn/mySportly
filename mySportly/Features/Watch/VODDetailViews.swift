import SwiftUI

/// A movie: artwork, Play or Resume, then the details.
struct MovieDetailView: View {
    @Environment(AppStore.self) private var store
    let movie: Movie
    @State private var detail: MovieDetail?

    var body: some View {
        let progress = store.progressItem(for: movie)
        let duration = detail?.duration ?? (progress.duration > 0 ? progress.duration : nil)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VODHeader(artwork: movie.poster, backdrop: detail?.backdrop, title: movie.title,
                          facts: [(movie.year ?? detail?.year).map(String.init), duration?.watchDuration, detail?.genre.nonEmpty, movie.rating.map { "★ \($0.formatted(.number.precision(.fractionLength(1))))" }])
                VStack(spacing: 10) {
                    PlayButton(progress: progress) { store.play(movie) }
                    if progress.resumePosition != nil {
                        Button("Play from Beginning", systemImage: "arrow.counterclockwise") { store.play(movie, fromStart: true) }
                            .buttonStyle(.glass).controlSize(.large).frame(maxWidth: .infinity)
                    }
                    WatchedButton(progress: progress)
                }
                if let plot = detail?.plot.nonEmpty { Text(plot).font(.body) }
                if let director = detail?.director.nonEmpty { LabeledContent("Director", value: director).font(.subheadline) }
                if let cast = detail?.cast.nonEmpty { LabeledContent("Cast") { Text(cast).multilineTextAlignment(.trailing) }.font(.subheadline) }
            }
            .padding()
        }
        .navigationTitle(movie.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { detail = await store.vod.detail(for: movie, provider: store.provider, demo: store.demo) }
    }
}

/// A show: Play the next episode, then seasons and episodes.
struct SeriesDetailView: View {
    @Environment(AppStore.self) private var store
    let show: Series
    @State private var detail: SeriesDetail?
    @State private var loading = true
    @State private var season = 0

    var body: some View {
        let progress = store.watchProgress
        let upNext = detail.flatMap { ContinueWatching.upNext(in: $0, progress: progress) }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VODHeader(artwork: show.poster, backdrop: detail?.backdrop, title: show.title,
                          facts: [show.year.map(String.init), detail.map { "\($0.seasons.count) \($0.seasons.count == 1 ? "Season" : "Seasons")" }, show.genre.nonEmpty])
                if let upNext, let detail {
                    let item = store.progressItem(for: upNext, of: show)
                    PlayButton(progress: item, label: upNext.code) { store.play(upNext, of: show, in: detail) }
                }
                if !show.plot.isEmpty { Text(show.plot).font(.body) }
                if let detail, !detail.seasons.isEmpty {
                    let current = detail.seasons.first { $0.number == season } ?? detail.seasons[0]
                    Picker("Season", selection: Binding(get: { current.number }, set: { season = $0 })) {
                        ForEach(detail.seasons) { Text($0.name).tag($0.number) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityIdentifier("season-picker")
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(current.episodes) { episode in
                            EpisodeRow(episode: episode, show: show, detail: detail)
                            if episode.id != current.episodes.last?.id { Divider() }
                        }
                    }
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Episodes aren’t available right now.").foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detail = await store.vod.detail(for: show, provider: store.provider, demo: store.demo)
            loading = false
            if let detail, season == 0 {
                season = ContinueWatching.upNext(in: detail, progress: store.watchProgress)?.season ?? detail.seasons.first?.number ?? 0
            }
        }
    }
}

private struct EpisodeRow: View {
    @Environment(AppStore.self) private var store
    let episode: Episode
    let show: Series
    let detail: SeriesDetail

    var body: some View {
        let progress = store.progressItem(for: episode, of: show)
        Button { store.play(episode, of: show, in: detail) } label: {
            HStack(alignment: .top, spacing: 12) {
                Poster(url: episode.still ?? show.poster, title: "", ratio: 16 / 9)
                    .frame(width: 128)
                    .overlay(alignment: .bottom) {
                        if progress.resumePosition != nil { ProgressView(value: progress.fraction).tint(.white).padding(6) }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Episode \(episode.number)").font(.caption).foregroundStyle(.secondary)
                    Text(episode.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if !episode.plot.isEmpty { Text(episode.plot).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    if let duration = episode.duration { Text(duration.watchDuration).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                if progress.isFinished {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).accessibilityLabel("Watched")
                }
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if progress.resumePosition != nil {
                Button("Play from Beginning", systemImage: "arrow.counterclockwise") { store.play(episode, of: show, in: detail, fromStart: true) }
            }
            Button(progress.isFinished ? "Mark as Unwatched" : "Mark as Watched", systemImage: progress.isFinished ? "circle" : "checkmark.circle") {
                store.setWatched(progress, !progress.isFinished)
            }
        }
        .accessibilityIdentifier("episode-\(episode.id)")
    }
}

/// Poster beside the title and facts, over a soft backdrop when there is one.
private struct VODHeader: View {
    let artwork: URL?
    let backdrop: URL?
    let title: String
    let facts: [String?]

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            Poster(url: artwork, title: title).frame(width: 120).shadow(radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title2.bold()).lineLimit(3)
                let line = facts.compactMap { $0 }.joined(separator: " · ")
                if !line.isEmpty { Text(line).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .background(alignment: .top) {
            if let backdrop {
                AsyncImage(url: backdrop) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(height: 180).clipped()
                    .mask(LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
                    .padding(.horizontal, -16).padding(.top, -16)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Play, or Resume with the time left.
private struct PlayButton: View {
    let progress: WatchProgress
    var label: String?
    let action: () -> Void

    var body: some View {
        let resuming = progress.resumePosition != nil
        Button(action: action) {
            VStack(spacing: 6) {
                Label([resuming ? "Resume" : "Play", label].compactMap { $0 }.joined(separator: " "), systemImage: "play.fill")
                    .font(.headline)
                if resuming {
                    HStack(spacing: 8) {
                        ProgressView(value: progress.fraction).frame(width: 80)
                        Text("\(progress.remaining.watchDuration) left").font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .accessibilityIdentifier("vod-play")
    }
}

private struct WatchedButton: View {
    @Environment(AppStore.self) private var store
    let progress: WatchProgress
    var body: some View {
        let watched = progress.isFinished
        Button(watched ? "Watched" : "Mark as Watched", systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle") {
            store.setWatched(progress, !watched)
        }
        .buttonStyle(.glass).controlSize(.large).frame(maxWidth: .infinity)
        .accessibilityIdentifier("vod-watched")
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
