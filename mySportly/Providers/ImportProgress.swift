import Foundation
import Observation

enum ImportStep: Int, CaseIterable, Identifiable, Sendable {
    case connection, channels, guide, saving
    var id: Self { self }
    var title: String {
        switch self {
        case .connection: "Connect"
        case .channels: "Channels"
        case .guide: "TV Guide"
        case .saving: "Save on This Device"
        }
    }
}

struct TransferProgress: Equatable, Sendable {
    let received: Int64
    let expected: Int64?
    init(received: Int64, expected: Int64) {
        self.received = max(0, received)
        self.expected = expected > 0 ? expected : nil
    }
    var fraction: Double? {
        guard let expected else { return nil }
        return min(1, Double(received) / Double(expected))
    }
    var description: String {
        let receivedText = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
        if let expected { return "\(receivedText) of \(ByteCountFormatter.string(fromByteCount: expected, countStyle: .file))" }
        return "\(receivedText) downloaded"
    }
}

enum GuideImportOutcome: Equatable, Sendable { case pending, loaded(Int), notProvided, unavailable }

/// A complete snapshot lets the UI coalesce frequent updates without losing counts.
struct ImportUpdate: Equatable, Sendable {
    var step: ImportStep
    var activity: String
    var transfer: TransferProgress?
    var channelCount: Int?
    var guide: GuideImportOutcome = .pending
}

/// Kept separate from AppStore so byte updates don't rebuild the channel lists.
@MainActor @Observable final class SourceImportProgress {
    let sourceName: String
    private(set) var update = ImportUpdate(step: .connection, activity: "Checking your connection…")
    init(sourceName: String) { self.sourceName = sourceName }

    func receive(_ update: ImportUpdate) {
        // A delegate callback queued just before completion must not replace Save.
        guard update.step.rawValue >= self.update.step.rawValue else { return }
        self.update = update
    }

    func beginSaving(_ result: ProviderImport) {
        let guide: GuideImportOutcome = result.programs.map { .loaded($0.count) } ?? (result.guideWarning == nil ? .notProvided : .unavailable)
        receive(ImportUpdate(step: .saving, activity: "Saving channels and guide for next time…", channelCount: result.channels.count, guide: guide))
    }

    func detail(for step: ImportStep) -> String? {
        if step == update.step { return update.transfer?.description ?? update.activity }
        guard step.rawValue < update.step.rawValue else { return nil }
        switch step {
        case .connection: return "Connected"
        case .channels: return update.channelCount.map { "\($0.formatted()) channels" }
        case .guide:
            switch update.guide {
            case .loaded(let count): return "\(count.formatted()) listings"
            case .notProvided: return "No guide provided"
            case .unavailable: return "Unavailable · saved guide kept if present"
            case .pending: return nil
            }
        case .saving: return nil
        }
    }
}
