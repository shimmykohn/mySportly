import SwiftUI
import AVKit
import Observation

@MainActor @Observable private final class MultiviewSlot: Identifiable {
    let id = UUID()
    let channel: Channel
    let player: AVPlayer
    var error: String?
    private var observer: NSKeyValueObservation?
    init(channel: Channel, url: URL) {
        self.channel = channel; player = AVPlayer(url: url); player.isMuted = true
        observer = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed { Task { @MainActor [weak self] in self?.error = "This stream could not be played. Try another channel or check the provider limit." } }
        }
        player.play()
    }
    func stop() { observer = nil; player.pause(); player.replaceCurrentItem(with: nil) }
}

struct MultiviewScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var slots: [MultiviewSlot] = []
    @State private var audioID: UUID?
    @State private var choosing = false
    @State private var replacing: UUID?
    @State private var layout = "Grid"
    @State private var message: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                if slots.isEmpty { ContentUnavailableView("Watch Together", systemImage: "rectangle.split.2x2", description: Text("Add up to four channels. Your subscription’s connection limit applies, and one stream plays audio.")) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: layout == "Stacked" || slots.count == 1 ? 1 : 2), spacing: 20) {
                    ForEach(slots) { slot in
                        VStack(alignment: .leading, spacing: 8) {
                            NativePlayerView(player: slot.player, controls: false).aspectRatio(16 / 9, contentMode: .fit)
                            Text(store.name(slot.channel)).font(.headline)
                            if let error = slot.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                            HStack {
                                Button(audioID == slot.id ? "Audio On" : "Listen", systemImage: audioID == slot.id ? "speaker.wave.2.fill" : "speaker.slash") { audioID = slot.id; updateAudio() }
                                Spacer()
                                Menu("Options", systemImage: "ellipsis.circle") {
                                    Button("Replace Channel") { replacing = slot.id; choosing = true }
                                    Button("Remove", role: .destructive) { remove(slot) }
                                }
                            }
                        }
                    }
                }.padding()
                if let message { Text(message).foregroundStyle(.secondary).padding() }
            }
            .navigationTitle("Multiview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem { Picker("Layout", selection: $layout) { Text("Grid").tag("Grid"); Text("Stacked").tag("Stacked") } }
                ToolbarItem(placement: .primaryAction) { Button("Add Channel", systemImage: "plus") { replacing = nil; choosing = true }.disabled(slots.count >= 4) }
            }
            .sheet(isPresented: $choosing) { NavigationStack { ChannelChooser(choose: add) } }
            .task {
                store.playback.stop()
                do { try await PlaybackAudioSession.shared.activate() } catch { message = "Audio output could not be activated." }
            }
            .onDisappear { slots.forEach { $0.stop() }; slots.removeAll(); store.multiviewCounts = [:] }
            .onChange(of: store.sources.map(\.id)) { _, active in
                for slot in slots.filter({ !active.contains($0.channel.sourceID) }) { remove(slot) }
            }
        }
    }
    private func add(_ channel: Channel) {
        do {
            guard let source = store.sources.first(where: { $0.id == channel.sourceID }) else { return }
            let existing = slots.filter { $0.channel.sourceID == source.id && $0.id != replacing }.count
            let recording = 0
            guard existing + recording < source.connectionLimit else { message = "\(source.name) allows \(source.connectionLimit) simultaneous connection(s). Remove a stream or stop recording first."; choosing = false; return }
            let url = try ProviderClient().playbackURL(channel, secrets: KeychainStore.credentials(channel.sourceID) ?? SourceSecrets())
            let replacingIndex = slots.firstIndex { $0.id == replacing }
            // Release the old provider connection before starting the replacement.
            if let replacingIndex { slots[replacingIndex].stop() }
            let new = MultiviewSlot(channel: channel, url: url)
            if let replacingIndex { let wasAudible = audioID == replacing; slots[replacingIndex] = new; if wasAudible { audioID = new.id } }
            else { slots.append(new) }
            if audioID == nil { audioID = new.id }
            updateAudio(); updateCounts(); choosing = false; message = nil
        } catch { message = store.safeError(error); choosing = false }
    }
    private func remove(_ slot: MultiviewSlot) { slot.stop(); slots.removeAll { $0.id == slot.id }; if audioID == slot.id { audioID = slots.first?.id }; updateAudio(); updateCounts() }
    private func updateAudio() { for slot in slots { slot.player.isMuted = slot.id != audioID } }
    private func updateCounts() { store.multiviewCounts = Dictionary(grouping: slots, by: { $0.channel.sourceID }).mapValues(\.count) }
}
