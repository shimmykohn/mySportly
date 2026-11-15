import Foundation

struct VODUpNext {
    let show: Series
    let episode: Episode
}

/// Movies and shows: loading, progress and what to play.
extension AppStore {
    func loadVOD(force: Bool = false) async {
        await vod.retitle(aiResults.vodNames ?? [:])
        let hadContent = vod.hasContent
        await vod.load(sources: sources, provider: provider, cache: cache, demo: demo, force: force)
        // New titles get tidied without waiting for the next launch.
        if vod.hasContent && (!hadContent || force) { runAIJobs() }
    }

    /// Saved progress by item, with the playing title's live position.
    var watchProgress: [String: WatchProgress] {
        var all: [String: WatchProgress] = [:]
        for key in personal.keys(prefix: "vod.progress.") {
            guard let item: WatchProgress = personal.value(key, default: nil) else { continue }
            all[item.itemID] = item
        }
        if let playing = nowPlayingVOD { all[playing.itemID] = playing }
        return all
    }
    var continueWatching: [WatchProgress] { ContinueWatching.items(Array(watchProgress.values)) }

    func progressItem(for movie: Movie) -> WatchProgress {
        watchProgress[movie.id] ?? WatchProgress(itemID: movie.id, kind: .movie, sourceID: movie.sourceID, providerID: movie.providerID,
                                                 container: movie.container, title: movie.title, subtitle: movie.year.map(String.init) ?? "", artwork: movie.poster)
    }
    func progressItem(for episode: Episode, of show: Series) -> WatchProgress {
        watchProgress[episode.id] ?? WatchProgress(itemID: episode.id, kind: .episode, sourceID: show.sourceID, providerID: episode.providerID,
                                                   container: episode.container, title: show.title, subtitle: "\(episode.code) · \(episode.title)",
                                                   artwork: show.poster, seriesID: show.id, duration: episode.duration ?? 0)
    }

    func play(_ movie: Movie, fromStart: Bool = false) {
        let item = progressItem(for: movie)
        playVOD(item, startAt: fromStart ? nil : item.resumePosition)
    }
    func play(_ episode: Episode, of show: Series, in detail: SeriesDetail?, fromStart: Bool = false) {
        let item = progressItem(for: episode, of: show)
        let next = detail.flatMap { ContinueWatching.nextEpisode(after: episode.id, in: $0) }.map { VODUpNext(show: show, episode: $0) }
        playVOD(item, startAt: fromStart ? nil : item.resumePosition, upNext: next)
    }
    /// From Continue Watching: picks up where it stopped; finds the next episode when the show is known.
    func resume(_ item: WatchProgress) {
        playVOD(item, startAt: item.resumePosition)
        guard let showID = item.seriesID, let show = vod.show(showID) else { return }
        Task {
            guard let detail = await vod.detail(for: show, provider: provider, demo: demo), nowPlayingVOD?.itemID == item.itemID,
                  let next = ContinueWatching.nextEpisode(after: item.itemID, in: detail) else { return }
            vodUpNext = VODUpNext(show: show, episode: next)
        }
    }
    func playUpNext() {
        guard let next = vodUpNext else { return }
        Task {
            let detail = await vod.detail(for: next.show, provider: provider, demo: demo)
            play(next.episode, of: next.show, in: detail, fromStart: true)
        }
    }

    func setWatched(_ item: WatchProgress, _ watched: Bool) {
        var updated = item
        updated.watched = watched; updated.updated = .now
        if !watched { updated.position = 0 }
        try? personal.set(WatchProgress.key(item.itemID), updated)
    }
    /// "Remove from Continue Watching".
    func clearProgress(_ item: WatchProgress) { try? personal.remove(WatchProgress.key(item.itemID)) }
}
