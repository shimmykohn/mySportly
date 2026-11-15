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
                        ZStack {
                            ChannelLogo(url: channel.logo).frame(width: 34, height: 34)
                            if store.playback.hasVideoFrame {
                                VideoLayerView(player: store.playback.player).background(.black)
                            }
                        }
                        .frame(width: 60, height: 34)
                        .clipShape(.rect(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(store.playerTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(store.playback.isLoading ? "Connecting…" : store.watchingTwo ? "\(store.name(channel)) + \(store.secondTitle)" : store.name(channel)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                Button("Stop", systemImage: "xmark") { store.stopPlayback() }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.primary)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("compact-player")
        }
    }
}

/// Full-screen player: the system video player (its own transport controls,
/// per the HIG) with the title and live progress below. Swipe down to
/// minimize; landscape on iPhone shows only the video. A second stream can
/// play under the first (side by side in landscape), one sound at a time.
struct PlayerScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var choosingSecond = false

    var body: some View {
        let video = NativePlayerView(player: store.playback.player, onDisplayChange: store.playback.videoDisplayChanged)
            .accessibilityLabel("Native video player")
            .accessibilityIdentifier("stream-preview")
            .accessibilityValue(store.playback.hasVideoFrame ? "Video ready" : "Waiting for video")
        Group {
            if verticalSizeClass == .compact {
                if store.watchingTwo {
                    HStack(spacing: 2) {
                        video.aspectRatio(16 / 9, contentMode: .fit)
                        SecondTile().aspectRatio(16 / 9, contentMode: .fit)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea().background(.black)
                } else {
                    video.ignoresSafeArea().background(.black)
                }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Button("Minimize", systemImage: "chevron.down") { dismiss() }
                            .labelStyle(.iconOnly).font(.title3.weight(.semibold))
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("close-player")
                        Spacer()
                        Button(store.watchingTwo ? "Change Second" : "Watch Two", systemImage: "rectangle.split.1x2") { choosingSecond = true }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("add-second-stream")
                    }
                    .padding(.horizontal).padding(.bottom, 10)
                    video
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(.black)
                    if store.watchingTwo {
                        TileCaption(title: store.playerTitle, subtitle: store.playerSubtitle, hasSound: !store.soundOnSecond) { store.focusSound(onSecond: false) }
                            .padding(.horizontal, 20).padding(.vertical, 10)
                        SecondTile()
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                        TileCaption(title: store.secondTitle, subtitle: store.secondSubtitle, hasSound: store.soundOnSecond, onClose: store.stopSecond) { store.focusSound(onSecond: true) }
                            .padding(.horizontal, 20).padding(.vertical, 10)
                    } else {
                        PlayerDetails().padding(.horizontal, 20).padding(.top, 22)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .sheet(isPresented: $choosingSecond) { SecondStreamPicker() }
    }
}

/// The second stream: video only, with its state over it.
private struct SecondTile: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let second = store.secondPlayback
        NativePlayerView(player: second.player, controls: false, pictureInPicture: false, onDisplayChange: second.videoDisplayChanged)
            .background(.black)
            .overlay {
                if let error = second.errorMessage {
                    VStack(spacing: 8) {
                        Text(error).font(.footnote).multilineTextAlignment(.center)
                        Button("Try Again") { second.retry() }.buttonStyle(.glass)
                    }
                    .foregroundStyle(.white).padding()
                } else if second.isLoading {
                    ProgressView().tint(.white)
                }
            }
            .overlay(alignment: .topLeading) {
                Button(store.soundOnSecond ? "Sound On" : "Sound Off", systemImage: store.soundOnSecond ? "speaker.wave.2.fill" : "speaker.slash.fill") {
                    store.focusSound(onSecond: !store.soundOnSecond)
                }
                .labelStyle(.iconOnly).font(.footnote.weight(.semibold))
                .buttonStyle(.glass).padding(8)
                .accessibilityIdentifier("second-sound")
            }
            .contentShape(.rect)
            .onTapGesture { store.focusSound(onSecond: true) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Second video")
            .accessibilityIdentifier("second-stream")
            .accessibilityValue(second.hasVideoFrame ? "Video ready" : "Waiting for video")
    }
}

/// Title row under each video in two-up viewing. Tap the speaker to hear that one.
private struct TileCaption: View {
    let title: String
    let subtitle: String
    let hasSound: Bool
    var onClose: (() -> Void)?
    let selectSound: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
            Button(hasSound ? "Playing Sound" : "Play Sound", systemImage: hasSound ? "speaker.wave.2.fill" : "speaker.slash") { selectSound() }
                .labelStyle(.iconOnly).font(.body).tint(hasSound ? .accentColor : .secondary)
                .accessibilityValue(hasSound ? "On" : "Off")
            if let onClose {
                Button("Close Second", systemImage: "xmark.circle.fill") { onClose() }
                    .labelStyle(.iconOnly).font(.title3).foregroundStyle(.secondary)
                    .accessibilityIdentifier("close-second-stream")
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerDetails: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let playback = store.playback
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.playerTitle).font(.headline).lineLimit(2)
                        .accessibilityIdentifier("player-title")
                        .accessibilityValue(Text(verbatim: playback.channel?.id ?? ""))
                    if !store.playerSubtitle.isEmpty { Text(store.playerSubtitle).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer()
                if let channel = playback.channel {
                    let favorite = store.flag(channel, "favorite")
                    Button(favorite ? "Remove Favorite" : "Favorite", systemImage: favorite ? "heart.fill" : "heart") { store.toggle(channel, "favorite") }
                        .labelStyle(.iconOnly).font(.title3).tint(favorite ? .pink : .secondary)
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
        }
    }
}
