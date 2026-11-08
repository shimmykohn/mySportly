import SwiftUI

extension EnvironmentValues {
    /// Shared with the full-screen player so it can zoom out of the tapped item.
    @Entry var playerNamespace: Namespace.ID?
}

private struct PlayerSource: ViewModifier {
    @Environment(\.playerNamespace) private var namespace
    let id: String
    func body(content: Content) -> some View {
        if let namespace { content.matchedTransitionSource(id: id, in: namespace) } else { content }
    }
}

extension View {
    /// Marks the view the player zooms out of when `store.playerSourceID == id`.
    func playerSource(_ id: String) -> some View { modifier(PlayerSource(id: id)) }
}
