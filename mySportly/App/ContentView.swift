import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Namespace private var playerNamespace
    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) { NavigationStack { HomeView().toolbarTitleDisplayMode(.inline) } }
            Tab("Guide", systemImage: "list.bullet.rectangle", value: AppTab.guide) { NavigationStack { GuideView().toolbarTitleDisplayMode(.inline) } }
            Tab("My Stuff", systemImage: "square.stack", value: AppTab.myStuff) { NavigationStack { MyStuffView().toolbarTitleDisplayMode(.inline) } }
            Tab("Watch", systemImage: "play.rectangle.on.rectangle", value: AppTab.watch) { NavigationStack { WatchView().toolbarTitleDisplayMode(.inline) } }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) { NavigationStack { SearchScreen().toolbarTitleDisplayMode(.inline) } }
        }
        .tabViewStyle(.sidebarAdaptable)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .tabViewBottomAccessory(isEnabled: store.playback.channel != nil) { CompactPlayer() }
        .environment(\.playerNamespace, playerNamespace)
        .sheet(isPresented: $store.showSetup) { SetupView().scrollEdgeEffectStyle(.soft, for: .top).interactiveDismissDisabled(store.sources.isEmpty && !store.demo) }
        .sheet(isPresented: $store.showSettings) { NavigationStack { SettingsView().toolbarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { store.showSettings = false } } } }.scrollEdgeEffectStyle(.soft, for: .top) }
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
            if store.flag(channel, "favorite") { Image(systemName: "heart.fill").foregroundStyle(.pink).accessibilityLabel("Favorite") }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PlayableChannelRow: View {
    @Environment(AppStore.self) private var store
    let channel: Channel
    var body: some View {
        Button { store.play(channel, source: "channel.\(channel.id)") } label: { ChannelRow(channel: channel).contentShape(.rect) }
            .playerSource("channel.\(channel.id)")
            .buttonStyle(.plain)
            .accessibilityIdentifier("play-channel-\(channel.id)")
            .accessibilityHint("Plays this channel")
            .contextMenu {
                Button("Watch", systemImage: "play") { store.play(channel) }
                Button(store.flag(channel, "favorite") ? "Remove Favorite" : "Favorite", systemImage: store.flag(channel, "favorite") ? "heart.slash" : "heart") { store.toggle(channel, "favorite") }
                Button("Hide Channel", systemImage: "eye.slash") { store.toggle(channel, "hidden") }
            }
            .swipeActions(edge: .leading) { Button("Favorite", systemImage: "heart") { store.toggle(channel, "favorite") }.tint(.pink) }
    }
}
