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
