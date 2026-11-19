import SwiftUI

/// Download, its progress (tap to cancel), or Downloaded with Remove.
struct DownloadButton: View {
    @Environment(AppStore.self) private var store
    let item: WatchProgress

    var body: some View {
        let record = Downloads.shared.records[item.itemID]
        Group {
            switch record?.state {
            case .finished?:
                Menu {
                    Button("Remove Download", systemImage: "trash", role: .destructive) { Downloads.shared.remove(item.itemID) }
                } label: {
                    Label("Downloaded", systemImage: "arrow.down.circle.fill")
                }
            case .downloading?:
                Button { Downloads.shared.cancel(item.itemID) } label: {
                    Label { Text("Cancel Download") } icon: { DownloadRing(fraction: record?.fraction ?? 0) }
                }
                .accessibilityValue(Text((record?.fraction ?? 0).formatted(.percent.precision(.fractionLength(0)))))
            default:
                Button(record?.state == .failed ? "Retry Download" : "Download",
                       systemImage: record?.state == .failed ? "exclamationmark.arrow.circlepath" : "arrow.down") { store.download(item) }
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass).buttonBorderShape(.circle)
        .accessibilityIdentifier("vod-download")
    }
}

/// The download actions for a long-press menu.
struct DownloadMenuItems: View {
    @Environment(AppStore.self) private var store
    let item: WatchProgress

    var body: some View {
        switch Downloads.shared.records[item.itemID]?.state {
        case .finished?:
            Button("Remove Download", systemImage: "trash", role: .destructive) { Downloads.shared.remove(item.itemID) }
        case .downloading?:
            Button("Cancel Download", systemImage: "xmark.circle") { Downloads.shared.cancel(item.itemID) }
        case .failed?:
            Button("Retry Download", systemImage: "arrow.clockwise") { store.download(item) }
            Button("Remove Download", systemImage: "trash", role: .destructive) { Downloads.shared.remove(item.itemID) }
        case nil:
            Button("Download", systemImage: "arrow.down.circle") { store.download(item) }
        }
    }
}

/// A small mark for lists: saved, or how far along.
struct DownloadBadge: View {
    let itemID: String

    var body: some View {
        switch Downloads.shared.records[itemID]?.state {
        case .finished?:
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.secondary).accessibilityLabel("Downloaded")
        case .downloading?:
            DownloadRing(fraction: Downloads.shared.records[itemID]?.fraction ?? 0, stop: false).accessibilityLabel("Downloading")
        case .failed?:
            Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary).accessibilityLabel("Download failed")
        case nil:
            EmptyView()
        }
    }
}

/// A saved movie or episode: tap to play from this device.
struct DownloadCard: View {
    @Environment(AppStore.self) private var store
    let record: DownloadRecord

    var body: some View {
        let item = store.progress(for: record.id) ?? record.item
        Button {
            switch record.state {
            case .finished: store.resume(item)
            case .failed: store.download(record.item)
            case .downloading: break
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Poster(url: record.artwork, title: record.item.title)
                    .overlay(alignment: .bottom) {
                        if record.state == .downloading {
                            ProgressView(value: record.fraction).tint(.white).padding(8)
                        } else if record.state == .finished, item.resumePosition != nil {
                            ProgressView(value: item.fraction).tint(.white).padding(8)
                        }
                    }
                Text(record.item.title).font(.caption).lineLimit(1)
                Text(caption(item)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 112)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if record.state == .finished {
                Button(item.resumePosition != nil ? "Resume" : "Play", systemImage: "play.fill") { store.resume(item) }
            }
            if record.state == .failed, let problem = record.problem { Text(problem) }
            DownloadMenuItems(item: record.item)
        }
        .accessibilityIdentifier("download-\(record.id)")
    }

    private func caption(_ item: WatchProgress) -> String {
        switch record.state {
        case .downloading: record.expected > 0 ? "Downloading · \(record.fraction.formatted(.percent.precision(.fractionLength(0))))" : "Downloading…"
        case .failed: "Download failed"
        case .finished: item.subtitle.isEmpty ? record.received.formatted(.byteCount(style: .file)) : item.subtitle
        }
    }
}

private struct DownloadRing: View {
    let fraction: Double
    var stop = true

    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.35), lineWidth: 2.5)
            Circle().trim(from: 0, to: max(0.03, fraction))
                .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if stop { Image(systemName: "stop.fill").font(.system(size: 7, weight: .bold)) }
        }
        .frame(width: 18, height: 18)
        .animation(.default, value: fraction)
    }
}

/// Settings → Downloads: what's saved, the space it takes, and removing it.
struct DownloadsSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmRemoveAll = false

    var body: some View {
        let records = Downloads.shared.records.values.sorted { $0.added > $1.added }
        let used = records.filter { $0.state == .finished }.reduce(Int64(0)) { $0 + $1.received }
        List {
            Section {
                LabeledContent("Space Used", value: used.formatted(.byteCount(style: .file)))
                    .accessibilityIdentifier("downloads-space")
            } footer: {
                Text("Downloads stay on this iPhone, aren’t backed up and play without a connection. One downloads at a time, since your provider counts it as a connection.")
            }
            if records.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle",
                                       description: Text("Download a movie or episode from its page or its long-press menu."))
            } else {
                Section {
                    ForEach(records) { record in
                        HStack(spacing: 12) {
                            Poster(url: record.artwork, title: record.item.title).frame(width: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                if !record.item.subtitle.isEmpty { Text(record.item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                Text(status(record)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                if record.state == .downloading { Downloads.shared.cancel(record.id) } else { Downloads.shared.remove(record.id) }
                            }
                        }
                        .contextMenu { DownloadMenuItems(item: record.item) }
                    }
                }
                Section {
                    Button("Remove All Downloads", role: .destructive) { confirmRemoveAll = true }
                        .accessibilityIdentifier("downloads-remove-all")
                }
            }
        }
        .navigationTitle("Downloads")
        .confirmationDialog("Remove all downloads?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
            Button("Remove All Downloads", role: .destructive) {
                for record in Downloads.shared.records.values {
                    if record.state == .downloading { Downloads.shared.cancel(record.id) } else { Downloads.shared.remove(record.id) }
                }
            }
        } message: {
            Text("This deletes \(used.formatted(.byteCount(style: .file))) of movies and episodes from this iPhone. You can download them again.")
        }
    }

    private func status(_ record: DownloadRecord) -> String {
        switch record.state {
        case .finished: record.received.formatted(.byteCount(style: .file))
        case .downloading: "Downloading · \(record.fraction.formatted(.percent.precision(.fractionLength(0))))"
        case .failed: record.problem ?? "Download failed"
        }
    }
}
