import SwiftUI
import ImageIO

/// TMDB's backdrops behind a movie or show page, cross-fading every eight
/// seconds while `rotating` (the hero is on screen). Holds still with Reduce
/// Motion, and shows the provider's art (`fallback`) until the first one
/// loads, or when there are none.
struct BackdropCarousel: View {
    let urls: [URL]
    let fallback: URL?
    var rotating = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Slide?
    /// The backdrop being faded from, kept underneath so nothing shows through.
    @State private var under: CGImage?
    /// Once a backdrop has faded in, the provider's art underneath goes.
    @State private var coversFallback = false

    private struct Slide { let url: URL; let image: CGImage }
    private struct Run: Equatable { let urls: [URL]; let rotate: Bool }

    var body: some View {
        let run = Run(urls: urls, rotate: rotating && !reduceMotion && urls.count > 1)
        ZStack {
            if !coversFallback {
                AsyncImage(url: fallback) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Rectangle().fill(.fill.tertiary) }
                }
            }
            if let under { Image(decorative: under, scale: 1).resizable().scaledToFill() }
            if let shown { Image(decorative: shown.image, scale: 1).resizable().scaledToFill().id(shown.url).transition(.opacity) }
        }
        .task(id: run) { await play(run) }
    }

    private func play(_ run: Run) async {
        guard !run.urls.isEmpty else {
            coversFallback = false; under = nil
            withAnimation(.easeInOut(duration: 0.6)) { shown = nil }
            return
        }
        // A new list starts at its best backdrop; a pause picks up where it was.
        if shown.map({ !run.urls.contains($0.url) }) ?? true { await show(run.urls, from: 0) }
        // Every eight seconds the next one, or another try at the first if none
        // has loaded; three failed turns in a row stop it.
        var misses = 0
        while !Task.isCancelled, misses < 3, run.rotate || shown == nil {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            let next = shown.flatMap { run.urls.firstIndex(of: $0.url) }.map { $0 + 1 } ?? 0
            misses = await show(run.urls, from: next) ? 0 : misses + 1
        }
    }

    /// Fades to the first backdrop from `start` on that loads; false when none did.
    @discardableResult private func show(_ urls: [URL], from start: Int) async -> Bool {
        for offset in urls.indices {
            let url = urls[(start + offset) % urls.count]
            if url == shown?.url { return false }
            guard let image = await ArtworkLoader.image(url) else { continue }
            guard !Task.isCancelled else { return false }
            under = shown?.image
            withAnimation(.easeInOut(duration: 1.6)) {
                shown = Slide(url: url, image: image)
            } completion: {
                // A newer fade may have started since; it tidies up after itself.
                guard shown?.url == url else { return }
                under = nil
                coversFallback = true
            }
            return true
        }
        return false
    }
}

/// Downloads and decodes artwork off the main thread; the shared URL cache
/// keeps a repeat off the network.
enum ArtworkLoader {
    static func image(_ url: URL) async -> CGImage? {
        await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let loaded = try? await URLSession.shared.data(from: url), (loaded.1 as? HTTPURLResponse)?.statusCode == 200,
                  let source = CGImageSourceCreateWithData(loaded.0 as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }.value
    }
}

/// TMDB's title logo in place of the title text. The text shows until the
/// logo loads (or when there's none), and stays the logo's spoken label.
struct TitleLogo<Fallback: View>: View {
    let url: URL?
    let title: String
    var maxWidth: CGFloat = 280
    var maxHeight: CGFloat = 110
    @ViewBuilder let fallback: Fallback

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.3))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
                    .accessibilityLabel(Text(title))
                    .transition(.opacity)
            } else {
                fallback
            }
        }
    }
}

/// TMDB's cast: photo, name and character.
struct CastRow: View {
    let cast: [TMDBCastMember]

    var body: some View {
        HomeRow(title: "Cast", identifier: "vod-cast") {
            ForEach(cast) { CastCard(member: $0) }
        }
    }
}

private struct CastCard: View {
    let member: TMDBCastMember

    var body: some View {
        VStack(spacing: 6) {
            AsyncImage(url: member.photo.flatMap { TMDBImage.url($0, size: .profile) }) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else {
                    Image(systemName: "person.fill").font(.title2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.fill.tertiary)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(.circle)
            .accessibilityHidden(true)
            Text(member.name).font(.caption.weight(.semibold)).lineLimit(2)
            if !member.character.isEmpty { Text(member.character).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
        }
        .multilineTextAlignment(.center)
        .frame(width: 84)
        .accessibilityElement(children: .combine)
    }
}

/// TMDB's official trailer, opened on YouTube.
struct TrailerButton: View {
    @Environment(\.openURL) private var openURL
    let url: URL

    var body: some View {
        Button("Trailer", systemImage: "play.rectangle") { openURL(url) }
            .buttonStyle(.glass)
            .controlSize(.large)
            .font(.headline)
            .accessibilityHint("Opens on YouTube")
            .accessibilityIdentifier("vod-trailer")
    }
}

extension TMDBTitle {
    /// "TMDB 8.4", so it isn't taken for the provider's stars.
    var ratingText: String? { rating.map { "TMDB \($0.formatted(.number.precision(.fractionLength(1))))" } }
    var backdropURLs: [URL] { backdrops.compactMap { TMDBImage.url($0, size: .backdrop) } }
    var logoURL: URL? { logo.flatMap { TMDBImage.url($0, size: .logo) } }
}
