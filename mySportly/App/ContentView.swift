import SwiftUI
import AppIntents

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Namespace private var playerNamespace
    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) { NavigationStack { HomeView() } }
            Tab("Guide", systemImage: "list.bullet.rectangle", value: AppTab.guide) { NavigationStack { GuideView() } }
            Tab("My Stuff", systemImage: "square.stack", value: AppTab.myStuff) { NavigationStack { LibraryView() } }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) { NavigationStack { SearchScreen() } }
        }
        .tabViewStyle(.sidebarAdaptable)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .tabViewBottomAccessory(isEnabled: store.playback.channel != nil) { CompactPlayer() }
        .environment(\.playerNamespace, playerNamespace)
        .sheet(isPresented: $store.showSetup) { SetupView().scrollEdgeEffectStyle(.soft, for: .top).interactiveDismissDisabled(store.sources.isEmpty && !store.demo) }
        .sheet(isPresented: $store.showSettings) { NavigationStack { SettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { store.showSettings = false } } } }.scrollEdgeEffectStyle(.soft, for: .top) }
        .fullScreenCover(isPresented: $store.showPlayer) {
            PlayerScreen().navigationTransition(.zoom(sourceID: store.playerSourceID ?? "player.accessory", in: playerNamespace))
        }
        .alert(store.notice?.title ?? "mySportly", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } }), presenting: store.notice) { _ in Button("OK", role: .cancel) { store.notice = nil } } message: { Text($0.message) }
        .overlay { if store.loading && store.selectedTab != .home { ProgressView("Opening your saved lineup…").padding().background(.background, in: .rect(cornerRadius: 12)).accessibilityIdentifier("catalog-loading") } }
    }
}

struct ChannelRow: View {
    @Environment(AppStore.self) private var store
    let channel: Channel
    var showProgram = true
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: channel.logo) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "tv").foregroundStyle(.secondary) }
                .frame(width: 40, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.name(channel)).font(.headline).foregroundStyle(.primary)
                if showProgram { Text(store.now(on: channel)?.title ?? "No guide information").font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                else { Text([store.category(channel), channel.quality].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            if store.flag(channel, "favorite") { Image(systemName: "star.fill").foregroundStyle(.secondary).accessibilityLabel("Favorite") }
        }
        .appEntityIdentifier(EntityIdentifier(for: ChannelEntity.self, identifier: channel.id))
        .accessibilityElement(children: .combine)
    }
}

struct PlayableChannelRow: View {
    @Environment(AppStore.self) private var store
    let channel: Channel
    var canRemoveFromHistory = false
    @State private var details = false
    var body: some View {
        Button { store.play(channel, source: "channel.\(channel.id)") } label: { ChannelRow(channel: channel).contentShape(.rect) }
            .playerSource("channel.\(channel.id)")
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(canRemoveFromHistory ? "recent" : "play")-channel-\(channel.id)")
            .accessibilityHint("Plays this channel")
            .contextMenu {
                Button("Watch", systemImage: "play") { store.play(channel) }
                LibrarySaveButton(item: store.bookmark(channel))
                Button(store.flag(channel, "favorite") ? "Remove Favorite" : "Add Favorite", systemImage: "star") { store.toggle(channel, "favorite") }
                Button("Channel Details", systemImage: "info.circle") { details = true }
                Button("Hide Channel", systemImage: "eye.slash") { store.toggle(channel, "hidden") }
            }
            .swipeActions(edge: .trailing) {
                if canRemoveFromHistory {
                    Button("Remove", systemImage: "clock.badge.xmark", role: .destructive) { store.removeFromHistory(channel) }
                        .accessibilityLabel("Remove from Recently Watched")
                }
                Button("Details", systemImage: "info.circle") { details = true }
            }
            .swipeActions(edge: .leading) { Button("Favorite", systemImage: "star") { store.toggle(channel, "favorite") }.tint(.orange) }
            .sheet(isPresented: $details) { NavigationStack { ChannelDetailView(channel: channel).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { details = false } } } } }
    }
}
