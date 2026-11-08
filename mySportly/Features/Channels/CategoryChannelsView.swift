import SwiftUI

struct CategoryChannelGroupRow: View {
    let group: CategoryChannelGroup
    var body: some View {
        NavigationLink {
            CategoryChannelsView(category: group.category)
        } label: {
            LabeledContent(group.category, value: group.count == 1 ? "1 channel" : "\(group.count.formatted()) channels")
        }.accessibilityIdentifier("category-group-\(group.id)")
    }
}

struct ExpandedCategorySection: View {
    let group: CategoryChannelGroup
    var body: some View {
        Section(group.category) {
            ForEach(group.subcategories) { TaxonomyBrowseRow(group: $0) }
            ForEach(group.preview) { PlayableChannelRow(channel: $0) }
            NavigationLink("See All \(group.category)") { CategoryChannelsView(category: group.category) }
                .accessibilityIdentifier("see-category-\(group.id)")
        }
    }
}

struct CategoryChannelsView: View {
    let category: String
    var body: some View { TaxonomyChannelsView(path: [category]) }
}
