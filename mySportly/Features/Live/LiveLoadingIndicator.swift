import SwiftUI

/// A single native spinner in the title position. Frequent progress updates
/// stay outside the channel list's observation boundary.
struct LiveLoadingIndicator: View {
    @Environment(AppStore.self) private var store
    let browser: ChannelBrowser

    private var activeWork: [String] {
        var work: [String] = []
        if store.loading { work.append("Opening saved lineup") }
        if store.personal.isSyncing { work.append("Syncing iCloud") }
        if store.importProgress != nil { work.append("Refreshing playlist") }
        if store.organization.isRunning { work.append("Organizing channels") }
        if store.preparingCatalog || browser.loading || store.favoritesToday.isUpdating { work.append("Preparing Live feed") }
        return work
    }
    var body: some View {
        if !activeWork.isEmpty {
            ProgressView().controlSize(.small)
                .accessibilityLabel("Loading")
                .accessibilityValue(activeWork.joined(separator: ", "))
                .accessibilityIdentifier("live-loading")
        }
    }
}
