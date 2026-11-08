import SwiftUI
import AVKit

/// The mini player in the tab bar accessory.
struct CompactPlayer: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if let channel = store.playback.channel {
            HStack(spacing: 12) {
                Button { store.playerSourceID = nil; store.showPlayer = true } label: {
                    HStack(spacing: 10) {
                        ChannelLogo(url: channel.logo).frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(store.playerTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(store.playback.isLoading ? "Connecting…" : store.name(channel)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .playerSource("player.accessory")
                .accessibilityLabel("Open player for \(store.name(channel))")
                Button(store.playback.isPlaying ? "Pause" : "Play", systemImage: store.playback.isPlaying ? "pause.fill" : "play.fill") { store.playback.toggle() }
                    .labelStyle(.iconOnly)
                Button("Stop", systemImage: "xmark") { store.playback.stop() }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.primary)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("compact-player")
        }
    }
}

/// Full-screen player: just the video and its controls. Swipe down to
/// minimize; landscape on iPhone shows only the video.
struct PlayerScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        let video = NativePlayerView(player: store.playback.player, onDisplayChange: store.playback.videoDisplayChanged)
            .accessibilityLabel("Native video player")
            .accessibilityIdentifier("stream-preview")
            .accessibilityValue(store.playback.hasVideoFrame ? "Video ready" : "Waiting for video")
        if verticalSizeClass == .compact {
            video.ignoresSafeArea().background(.black)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Button("Minimize", systemImage: "chevron.down") { dismiss() }
                        .labelStyle(.iconOnly).font(.title3.weight(.semibold))
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("close-player")
                    Spacer()
                }
                .padding(.horizontal).padding(.bottom, 10)
                video
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(.black)
                PlayerDetails().padding(.horizontal, 20).padding(.top, 22)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct PlayerDetails: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let playback = store.playback
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.playerTitle).font(.title2.bold()).lineLimit(2)
                        .accessibilityIdentifier("player-title")
                        .accessibilityValue(Text(verbatim: playback.channel?.id ?? ""))
                    if !store.playerSubtitle.isEmpty { Text(store.playerSubtitle).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer()
                if let channel = playback.channel {
                    let favorite = store.flag(channel, "favorite")
                    Button(favorite ? "Remove Favorite" : "Favorite", systemImage: favorite ? "heart.fill" : "heart") { store.toggle(channel, "favorite") }
                        .labelStyle(.iconOnly).font(.title2).tint(favorite ? .pink : .secondary)
                        .accessibilityIdentifier("player-favorite")
                }
            }
            if let error = playback.errorMessage {
                HStack {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    Button("Try Again") { playback.retry() }
                }
            } else if playback.isLoading {
                Text(playback.hasVideoFrame ? "Buffering…" : "Connecting…").font(.subheadline).foregroundStyle(.secondary)
            } else if let notice = playback.playbackNotice {
                Text(notice).font(.subheadline).foregroundStyle(.secondary)
            }
            if let channel = playback.channel, let program = store.now(on: channel) {
                VStack(spacing: 4) {
                    ProgressView(value: min(1, max(0, store.clock.timeIntervalSince(program.start) / program.end.timeIntervalSince(program.start))))
                    HStack {
                        Text(program.start, format: .dateTime.hour().minute())
                        Spacer()
                        Text(program.end, format: .dateTime.hour().minute())
                    }
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 44) {
                Button("Previous Channel", systemImage: "backward.fill") { store.stepChannel(by: -1) }
                Button(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill") { playback.toggle() }
                    .font(.largeTitle)
                Button("Next Channel", systemImage: "forward.fill") { store.stepChannel(by: 1) }
            }
            .labelStyle(.iconOnly).font(.title).tint(.primary)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
    }
}

struct ChannelChooser: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let choose: (Channel) -> Void
    @State private var search = ""
    @State private var browser = ChannelBrowser()
    @State private var limit = 100
    private var request: ChannelBrowseRequest {
        var request = ChannelBrowseRequest(); request.query = search; request.collapseVariants = true; request.audience = store.audience; return request
    }
    var body: some View {
        List {
            Section { LineupScopeControl() }
            if browser.loading { ProgressView("Finding channels…") }
            ForEach(browser.channels.prefix(limit)) { channel in
                Button { choose(channel) } label: { ChannelRow(channel: channel) }.buttonStyle(.plain)
            }
            MoreChannelsRow(total: browser.channels.count, limit: $limit)
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always)).navigationTitle("Choose Channel")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .task(id: BrowseTaskID(revision: store.queryRevision, request: request)) {
            limit = 100
            await browser.update(directory: store.directory, request: request)
        }
    }
}
