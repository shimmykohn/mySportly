import SwiftUI

struct SourceImportProgressSection: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if let progress = store.importProgress {
            Section {
                SourceImportProgressView(progress: progress)
                if !store.refreshingSource { Button("Cancel Import", role: .cancel) { store.cancelImport() } }
            } header: {
                Text("Updating \(progress.sourceName)")
            } footer: {
                Text("Keep mySportly open until saving finishes. Your saved lineup will be ready the next time you open the app.")
            }
        }
    }
}

struct SourceImportProgressView: View {
    let progress: SourceImportProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step \(progress.update.step.rawValue + 1) of \(ImportStep.allCases.count)")
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("source-import-step")
            ForEach(ImportStep.allCases) { step in
                HStack(alignment: .top, spacing: 12) {
                    Group {
                        if step.rawValue < progress.update.step.rawValue {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        } else if step == progress.update.step {
                            ProgressView()
                        } else {
                            Image(systemName: "circle").foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 22, height: 22).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title).font(.headline)
                        if let detail = progress.detail(for: step) {
                            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                                .accessibilityIdentifier(step == progress.update.step ? "source-import-detail" : "source-import-completed-\(step.rawValue)")
                        }
                        if step == progress.update.step, let fraction = progress.update.transfer?.fraction {
                            ProgressView(value: fraction)
                                .accessibilityLabel("\(step.title) download")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
