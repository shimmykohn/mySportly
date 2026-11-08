import SwiftUI

struct SportsFollowingView: View {
    @Environment(AppStore.self) private var store
    @State private var kind: SportsFollowKind
    @State private var query = ""
    @State private var searchPresented = false
    init(kind: SportsFollowKind = .league) { _kind = State(initialValue: kind) }
    private var saved: [SportsLibraryItem] { store.sportsMembership.directItems.filter { $0.kind == kind } }
    private var choices: [SportsFollowChoice] {
        store.sportsData.index.choices.filter {
            $0.kind == kind && (query.isEmpty || ([$0.name, $0.league] + $0.aliases).contains { $0.localizedStandardContains(query) })
        }
    }
    var body: some View {
        let savedIDs = Set(store.sportsLibrary.map(\.id))
        List {
            Section {
                Picker("Browse", selection: $kind) { ForEach(SportsFollowKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            } footer: { Text("Saving a league adds one item. Open it to browse teams, then save any teams you want separately. Favorites control which broadcasts appear on Live today.") }
            if query.isEmpty && !saved.isEmpty {
                Section("In Your Library") { ForEach(saved) { SportsLibraryRow(item: $0) } }
            }
            Section(query.isEmpty ? "Find \(kind.rawValue)" : "Results") {
                ForEach(choices) { choice in
                    let item = SportsLibraryItem(name: choice.name, kind: kind)
                    let included = savedIDs.contains(item.id)
                    HStack {
                        NavigationLink { SportsLibraryItemView(item: item) } label: { SportsLibraryLabel(item: item) }
                        Button(included ? "Remove \(item.name) from Library" : "Add \(item.name) to Library", systemImage: included ? "checkmark.circle.fill" : "plus.circle") {
                            included ? store.removeSportsItem(item) : store.saveSportsItem(item)
                        }.labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
                let custom = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if custom.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains),
                   !savedIDs.contains(SportsLibraryItem(name: custom, kind: kind).id),
                   SportsFollowCatalog.choice(named: custom) == nil {
                    Button("Add “\(custom)” to Library", systemImage: "plus") {
                        store.saveSportsItem(SportsLibraryItem(name: custom, kind: kind)); query = ""
                    }
                }
            }
        }
        .searchable(text: $query, isPresented: $searchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: kind == .team ? "Search teams or add your own" : "Search leagues or add your own")
        .onSubmit(of: .search) { searchPresented = false }
        .navigationTitle("Add to Library").navigationBarTitleDisplayMode(.inline)
    }
}
