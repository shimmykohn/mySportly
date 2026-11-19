import SwiftUI

/// A Liquid Glass pill floating over Home while a source refreshes (its four
/// steps) or the AI is organizing, then a few seconds of what the AI changed.
struct HomeActivityPill: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if let progress = store.importProgress {
                let step = progress.update.step
                let within = progress.update.transfer?.fraction ?? 0
                Pill(symbol: "arrow.triangle.2.circlepath", effect: .spin,
                     title: "Refreshing \(progress.sourceName)",
                     detail: "Step \(step.rawValue + 1) of \(ImportStep.allCases.count) · \(step.title)",
                     fraction: (Double(step.rawValue) + within) / Double(ImportStep.allCases.count))
                    .id("refresh")
            } else if let activity = store.aiActivity {
                Pill(symbol: "sparkles", effect: .pulse, title: "AI is organizing your lineup", detail: activity, fraction: store.aiFraction)
                    .id("ai")
            } else if let summary = store.aiSummary {
                Pill(symbol: "checkmark.seal.fill", effect: nil, title: "AI finished", detail: summary.prefix(1).uppercased() + summary.dropFirst(), fraction: nil)
                    .id("done")
                    .onTapGesture { store.aiSummary = nil }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .animation(.smooth, value: store.importProgress?.update.step)
        .animation(.smooth, value: store.aiActivity == nil)
        .animation(.smooth, value: store.aiSummary)
    }
}

private struct Pill: View {
    enum Effect { case spin, pulse }
    let symbol: String
    let effect: Effect?
    let title: String
    let detail: String
    let fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                icon
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            if let fraction {
                ProgressView(value: max(0.02, fraction))
                    .animation(.smooth, value: fraction)
            }
        }
        .padding(14)
        .frame(maxWidth: 520)
        .glassEffect(in: .rect(cornerRadius: 22))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-activity")
    }

    @ViewBuilder private var icon: some View {
        switch effect {
        case .spin?: Image(systemName: symbol).symbolEffect(.rotate, options: .repeat(.continuous))
        case .pulse?: Image(systemName: symbol).symbolEffect(.pulse, options: .repeat(.continuous))
        case nil: Image(systemName: symbol)
        }
    }
}
