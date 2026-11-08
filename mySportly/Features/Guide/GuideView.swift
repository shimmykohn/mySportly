import SwiftUI
import Translation

struct GuideView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var chosenDate = Date.now
    @State private var followsNow = true
    @State private var filter = "For You"
    @State private var timeline = false
    @State private var query = ""
    @State private var visibleChannelCount = 100
    @State private var browser = ChannelBrowser()
    @State private var sheet: GuideSheet?
    private enum GuideSheet: String, Identifiable { case filters, time; var id: String { rawValue } }
    private var date: Date { followsNow ? store.clock : chosenDate }
    private var withListingsOnly: Bool { store.personal.value("preferences.guideWithListings", default: true) }
    private struct RequestID: Equatable { let browse: BrowseTaskID; let date: Date; let withListings: Bool }
    private var request: ChannelBrowseRequest {
        var request = ChannelBrowseRequest()
        request.query = query; request.collapseVariants = true; request.excludeInactive = true
        request.audience = store.audience
        request.ranked = filter == "For You"; request.favoritesOnly = filter == "Favorites"
        request.sportsOnly = filter == "Sports"; request.preferredLanguagesOnly = filter == "Languages"
        return request
    }
    var body: some View {
        let matchingChannels = browser.channels
        let visibleChannels = Array(matchingChannels.prefix(visibleChannelCount))
        Group {
            if timeline && sizeClass == .regular && !typeSize.isAccessibilitySize {
                ScrollView {
                    guideSummary.padding()
                    GuideTimeline(channels: visibleChannels, date: date)
                    moreChannels(total: matchingChannels.count).padding()
                }
            } else {
                List {
                    if browser.loading || store.preparingCatalog { ProgressView("Preparing guide…") }
                    if store.demo { Label("Sample guide", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
                    if !store.preparingCatalog && !store.loading && store.channels.isEmpty {
                        ContentUnavailableView("Connect a Source", systemImage: "list.bullet.rectangle", description: Text("Your provider’s guide appears here after import."))
                    } else if !browser.loading && !store.preparingCatalog && matchingChannels.isEmpty {
                        ContentUnavailableView {
                            Label("No Matching Listings", systemImage: "list.bullet.rectangle")
                        } description: { Text("Try another time or adjust your guide filters.") }
                        actions: { Button("Guide Filters") { sheet = .filters } }
                    }
                    Section {
                        ForEach(visibleChannels) { channel in
                            NavigationLink { ChannelScheduleView(channel: channel, date: date) } label: {
                                GuideChannelRow(channel: channel, date: date)
                            }.accessibilityIdentifier("guide-channel-\(channel.id)")
                        }
                        moreChannels(total: matchingChannels.count)
                    } header: { guideSummary }
                }
            }
        }
        .navigationTitle("Guide")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search channels")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Now") { followsNow = true; store.clock = .now }
                    Button("Tonight") {
                        chosenDate = max(store.clock, Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: store.clock) ?? store.clock)
                        followsNow = false
                    }
                    Button("Choose Date and Time", systemImage: "calendar") { sheet = .time }
                } label: { Label(followsNow ? "Now" : date.formatted(date: .omitted, time: .shortened), systemImage: "calendar") }
                .accessibilityLabel("Guide Time")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Guide Filters", systemImage: filter == "For You" ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") { sheet = .filters }
            }
        }
        .sheet(item: $sheet) { selection in
            NavigationStack {
                Form {
                    if selection == .filters {
                        Section("Channels") {
                            LineupScopeControl()
                            Picker("Filter", selection: $filter) { ForEach(["For You", "All", "Favorites", "Sports", "Languages"], id: \.self) { Text($0) } }
                            Toggle("Only Channels with Listings", isOn: Binding(get: { withListingsOnly }, set: { store.set("preferences.guideWithListings", $0) }))
                        }
                        if sizeClass == .regular { Section("Layout") { Toggle("Timeline", isOn: $timeline) } }
                        Section { NavigationLink("TV Guide Status") { GuideStatusView() } }
                    } else {
                        DatePicker("Guide Time", selection: Binding(get: { date }, set: { chosenDate = $0; followsNow = false }), displayedComponents: [.date, .hourAndMinute])
                        Button("Return to Now") { followsNow = true; store.clock = .now; sheet = nil }
                    }
                }
                .navigationTitle(selection == .filters ? "Guide Filters" : "Guide Time")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark") { sheet = nil }.labelStyle(.iconOnly).tint(.primary).accessibilityIdentifier("close-guide-options")
                    }
                }
            }.presentationDetents([.large])
        }
        .onChange(of: query) { _, _ in visibleChannelCount = 100 }
        .onChange(of: filter) { _, _ in visibleChannelCount = 100 }
        .task(id: RequestID(browse: BrowseTaskID(revision: store.queryRevision, request: request, preferences: store.personal.revision), date: date, withListings: withListingsOnly)) {
            do {
                let date = date, index = store.queryIndex
                let matching = withListingsOnly ? try await catalogWork { try index?.channelsWithListings(from: date, to: date + 6 * 3600) ?? [] } : nil
                try Task.checkCancellation()
                await browser.update(directory: store.directory, request: request, preferences: store.recommendationPreferences, matchingIDs: matching)
            } catch { }
        }
    }
    private var guideSummary: some View {
        HStack {
            Text(followsNow ? "Now & Next" : date.formatted(date: .abbreviated, time: .shortened))
            Spacer()
            Text("\(browser.channels.count) Channels").accessibilityIdentifier("guide-channel-count").accessibilityValue(String(browser.channels.count))
        }.font(.subheadline).foregroundStyle(.secondary)
    }
    @ViewBuilder private func moreChannels(total: Int) -> some View {
        if total > visibleChannelCount { Button("Show More Channels", systemImage: "plus") { visibleChannelCount += 100 } }
    }
}

private struct GuideChannelRow: View {
    @Environment(AppStore.self) private var store
    let channel: Channel
    let date: Date
    var body: some View {
        let programs = store.programs(for: channel).filter { $0.end > date && $0.start < date + 6 * 3600 && !ListingAvailability.isPlaceholderProgram($0.title) }
        VStack(alignment: .leading, spacing: 4) {
            Text(store.name(channel)).font(.subheadline).foregroundStyle(.secondary)
            if let current = programs.first {
                Text(current.start > date ? "Later · \(current.title)" : current.title).font(.headline).lineLimit(2)
                Text("\(current.start.formatted(date: .omitted, time: .shortened)) – \(current.end.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                if let next = programs.dropFirst().first { Text("Next · \(next.title)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            } else { Text("No listings available").foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine)
    }
}

struct ChannelScheduleView: View {
    @Environment(AppStore.self) private var store
    let channel: Channel
    let date: Date
    var body: some View {
        let programs = store.programs(for: channel).filter { $0.end > date && $0.start < date + 24 * 3600 && !ListingAvailability.isPlaceholderProgram($0.title) }
        List {
            Section {
                Button("Watch Channel", systemImage: "play.fill") { store.play(channel) }
            }
            Section("Schedule") {
                ForEach(programs) { program in NavigationLink { ProgramDetailView(program: program, channel: channel) } label: { ProgramRow(program: program) } }
                if programs.isEmpty { Text("No guide listings for this time.").foregroundStyle(.secondary) }
            }
            Section { NavigationLink("Guide Mapping") { GuideMappingView(channel: channel) } }
        }.navigationTitle(store.name(channel)).navigationBarTitleDisplayMode(.inline)
    }
}

struct ProgramRow: View {
    @Environment(AppStore.self) private var store
    let program: GuideProgram
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(program.title).font(.headline)
            Text("\(program.start.formatted(date: .omitted, time: .shortened)) – \(program.end.formatted(date: .omitted, time: .shortened))").font(.subheadline).foregroundStyle(.secondary)
            if program.isLive(at: store.clock) {
                ProgressView(value: min(1, max(0, store.clock.timeIntervalSince(program.start) / program.end.timeIntervalSince(program.start))))
                    .accessibilityLabel("Program progress")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct GuideTimeline: View {
    @Environment(AppStore.self) private var store
    let channels: [Channel]; let date: Date
    var body: some View {
        ScrollView(.horizontal) {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 0) {
                    Text("Channel").frame(width: 160, alignment: .leading)
                    ForEach(0..<6) { hour in Text(date.addingTimeInterval(Double(hour * 3600)), style: .time).frame(width: 120, alignment: .leading) }
                }.font(.caption).foregroundStyle(.secondary)
                ForEach(channels) { channel in
                    HStack(spacing: 0) {
                        Button(store.name(channel)) { store.play(channel) }.frame(width: 160, alignment: .leading).lineLimit(3)
                        ZStack(alignment: .leading) {
                            ForEach(store.programs(for: channel).filter { $0.end > date && $0.start < date.addingTimeInterval(21600) }) { program in
                                let start = max(0, program.start.timeIntervalSince(date) / 30)
                                let end = min(720, program.end.timeIntervalSince(date) / 30)
                                NavigationLink { ProgramDetailView(program: program, channel: channel) } label: {
                                    Text(program.title).font(.subheadline).lineLimit(3).frame(width: max(1, end - start - 4), height: 70, alignment: .leading)
                                        .background(.quaternary, in: .rect(cornerRadius: 6)).clipped()
                                }.buttonStyle(.plain).offset(x: start)
                            }
                        }.frame(width: 720, height: 80, alignment: .leading)
                    }
                }
            }.padding()
        }
        .accessibilityLabel("Six-hour program timeline. Switch to the list for larger text.")
    }
}

struct GuideMappingView: View {
    @Environment(AppStore.self) private var store
    let channel: Channel
    @State private var guideID = ""
    @State private var offset = 0
    @State private var search = ""
    @State private var loaded = false
    var body: some View {
        Form {
            Section("Time Correction") {
                Stepper("Offset: \(offset) minutes", value: $offset, in: -1440...1440, step: 15)
                Text("Adjust only if this channel’s guide is shifted. Program times already use your device’s time zone.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Channel Mapping") {
                if store.personal.has(store.key(channel, "guideID")) {
                    Label("Your saved mapping", systemImage: "person.crop.circle")
                } else if let match = store.guideMatches[channel.id] {
                    Label("Matched on This Device", systemImage: "link")
                    Text(match.reason + ". No AI was used.").font(.footnote).foregroundStyle(.secondary)
                } else { Text("Using the provider’s guide ID").foregroundStyle(.secondary) }
                TextField("Guide Channel ID", text: $guideID).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Find a guide channel", text: $search)
                ForEach(store.guideIDs(for: channel.sourceID).filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }.prefix(100), id: \.self) { id in
                    Button { guideID = id } label: { HStack { Text(id); Spacer(); if id == guideID { Image(systemName: "checkmark") } } }
                }
            }
            Section {
                Button("Save Mapping") { store.saveGuideMapping(channel, guideID: guideID, offset: offset) }
                Button("Use Automatic Mapping") { store.saveGuideMapping(channel, guideID: nil, offset: nil); guideID = store.automaticGuideID(for: channel); offset = 0 }
                Button("Use Provider ID Only") { store.saveGuideMapping(channel, guideID: channel.guideID, offset: nil); guideID = channel.guideID; offset = 0 }
            }
        }
        .navigationTitle("Guide Mapping")
        .task { guard !loaded else { return }; loaded = true; guideID = store.guideID(for: channel); offset = store.personal.value(store.key(channel, "guideOffset"), default: 0) }
    }
}

struct ProgramDetailView: View {
    @Environment(AppStore.self) private var store
    let program: GuideProgram; let channel: Channel
    @State private var minutesBefore = 0
    @State private var translated: String?
    @State private var translation: TranslationSession.Configuration?
    private var spoilersHidden: Bool { store.spoilerFree && program.isSports }
    private var catchupAvailable: Bool { channel.archiveDays > 0 && program.end <= store.clock && program.start > store.clock.addingTimeInterval(-Double(channel.archiveDays) * 86400) }
    var body: some View {
        List {
            Section {
                if !spoilersHidden, let image = program.image { AsyncImage(url: image) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }.frame(maxHeight: 220).accessibilityHidden(true) }
                Text(program.title).font(.title2.bold())
                Text(store.name(channel)).foregroundStyle(.secondary)
                Text(program.start.formatted(date: .complete, time: .shortened))
                Text("Until \(program.end.formatted(date: .omitted, time: .shortened)) · \(TimeZone.current.abbreviation() ?? "Local time")").font(.subheadline).foregroundStyle(.secondary)
                if program.isLive(at: store.clock) { Button("Watch Live", systemImage: "play.fill") { store.play(channel) } }
                else if catchupAvailable { Button("Watch Catch-up", systemImage: "gobackward") { store.play(channel, program: program) } }
                else if program.end <= store.clock { Text("Catch-up is unavailable for this program.").foregroundStyle(.secondary) }
            }
            if spoilersHidden { Section { Label("Sports descriptions and artwork are hidden", systemImage: "eye.slash") } }
            else if !program.summary.isEmpty {
                Section("Description") {
                    Text(program.summary).textSelection(.enabled)
                    Button("Translate Description", systemImage: "translate") { translation = TranslationSession.Configuration(source: nil, target: Locale.Language(identifier: store.personal.value("preferences.guideLanguage", default: store.languages.first ?? "en"))) }
                    if let translated { Text(translated); Text("Translated description · Original retained above").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if program.start > store.clock {
                Section("Reminder") {
                    Picker("Notify Me", selection: $minutesBefore) { Text("At Start").tag(0); Text("5 Minutes Before").tag(5); Text("15 Minutes Before").tag(15) }
                    Button("Set Reminder", systemImage: "bell.badge") { Task { do { try await store.reminders.schedule(program: program, channel: channel, minutesBefore: minutesBefore); store.inform("Reminder saved", "You’ll be notified on this device before the program starts.") } catch { store.inform("Reminder unavailable", error.localizedDescription) } } }
                }
            }
            Section { NavigationLink("Channel Details") { ChannelDetailView(channel: channel) } }
        }
        .navigationTitle("Program").navigationBarTitleDisplayMode(.inline)
        .translationTask(translation) { session in
            do { translated = try await session.translate(program.summary).targetText }
            catch { store.inform("Translation unavailable", "The selected language could not be translated. The original description remains available.") }
        }
    }
}
