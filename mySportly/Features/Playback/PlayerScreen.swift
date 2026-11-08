import SwiftUI
import AVKit

struct CompactPlayer: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if let channel = store.playback.channel {
            HStack(spacing: 12) {
                Button { store.showPlayer = true } label: {
                    HStack { Image(systemName: "play.tv"); VStack(alignment: .leading) { Text(store.name(channel)).font(.subheadline.bold()).lineLimit(1); if store.playback.isLoading { Text("Connecting…").font(.caption).foregroundStyle(.secondary) } } }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityLabel("Open player for \(store.name(channel))")
                Button(store.playback.isPlaying ? "Pause" : "Play", systemImage: store.playback.isPlaying ? "pause.fill" : "play.fill") { store.playback.toggle() }.labelStyle(.iconOnly)
                Button("Stop", systemImage: "xmark") { store.playback.stop() }.labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.primary)
            }.padding(.horizontal)
        }
    }
}

struct PlayerScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var channels = false
    @State private var showRecordAlert = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Keep one native player mounted as soon as the sheet opens.
                // The native progress row never replaces the video surface.
                NativePlayerView(player: store.playback.player, onDisplayChange: store.playback.videoDisplayChanged)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxHeight: 360)
                    .frame(maxWidth: .infinity)
                    .background(.black)
                    .accessibilityLabel("Native video player")
                    .accessibilityIdentifier("stream-preview")
                    .accessibilityValue(store.playback.hasVideoFrame ? "Video ready" : "Waiting for video")
                List {
                    Section {
                        if store.playback.isLoading { ProgressView(store.playback.hasVideoFrame ? "Buffering…" : "Connecting to stream…") }
                        else if store.playback.isPlaying && !store.playback.hasVideoFrame && !store.playback.videoUnavailable { ProgressView("Waiting for video…") }
                        if let notice = store.playback.playbackNotice { Label(notice, systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary) }
                        if let channel = store.playback.channel {
                            Text(store.name(channel)).font(.title2.bold())
                            if let program = store.now(on: channel) { NavigationLink { ProgramDetailView(program: program, channel: channel) } label: { ProgramRow(program: program) } }
                        }
                        if let error = store.playback.errorMessage { Text(error).foregroundStyle(.secondary); Button("Try Again", systemImage: "arrow.clockwise") { store.playback.retry() } }
                    }
                    Section("Playback") {
                        Button("Previous Channel", systemImage: "backward.end") { store.previousChannel() }.disabled(store.playback.previous == nil)
                        Button("Change Channel", systemImage: "list.bullet") { channels = true }
                        NativeStreamPickers()
                        if let channel = store.playback.channel { NavigationLink("Channel Details") { ChannelDetailView(channel: channel) } }
                        Text("Use the player’s system controls for full screen, captions, audio tracks, picture in picture, and AirPlay when available.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Recording") {
                        if let recording = store.recorder.active {
                            Label("Recording \(recording.channelName)", systemImage: "record.circle")
                            Text("\(Duration.seconds(recording.duration).formatted(.time(pattern: .hourMinuteSecond))) · \(ByteCountFormatter.string(fromByteCount: recording.bytes, countStyle: .file))").monospacedDigit()
                            Button("Stop Recording", role: .destructive) { Task { await store.recorder.stop() } }
                        } else { Button("Record on This Device", systemImage: "record.circle") { showRecordAlert = true }.disabled(store.playback.channel == nil || store.playback.channel?.id.hasPrefix("recording.") == true) }
                        if let error = store.recorder.errorMessage { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    }
                }.accessibilityIdentifier("player-details")
            }
            .navigationTitle("Now Playing").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly).tint(.primary)
                        .accessibilityIdentifier("close-player")
                }
            }
            .sheet(isPresented: $channels) { NavigationStack { ChannelChooser { channel in store.play(channel); channels = false } } }
            .confirmationDialog("Start recording?", isPresented: $showRecordAlert, titleVisibility: .visible) { Button("Start Recording") { Task { await store.startRecording() } } } message: { Text("Keep the app in the foreground. This uses an additional provider connection and device storage. Supported unencrypted HLS streams can be recorded.") }
        }
    }
}

struct NativeStreamPickers: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let feeds = store.playerFeeds
        if !feeds.isEmpty {
            Picker("Stream", selection: Binding(get: { store.playback.channel?.id ?? "" }, set: { store.selectPlayerFeed($0) })) {
                ForEach(feeds) { channel in Text(store.name(channel)).tag(channel.id) }
            }.pickerStyle(.menu).accessibilityIdentifier("player-stream-picker")
        }
        if store.playback.supportsQualityPreference {
            Picker("Quality", selection: Binding(get: { store.playback.quality }, set: {
                store.playback.quality = $0; store.set("preferences.streamQuality", $0.rawValue)
            })) {
                ForEach(StreamQuality.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("player-quality-picker")
            Text("Quality is a preference for adaptive streams. Available resolutions depend on the feed.").font(.caption).foregroundStyle(.secondary)
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
