/// Previous and next channel, like a remote's channel buttons.
public enum ChannelStepping {
    /// The channel `offset` places away from `id`, wrapping at both ends. A
    /// channel not in the list starts from the first (forward) or last (back).
    public static func neighbor(of id: String?, in ids: [String], offset: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let id, let index = ids.firstIndex(of: id) else { return offset >= 0 ? ids.first : ids.last }
        let count = ids.count
        return ids[((index + offset) % count + count) % count]
    }
}
