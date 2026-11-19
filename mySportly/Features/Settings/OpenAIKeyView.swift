import SwiftUI

/// Settings → OpenAI: paste, replace or remove the key, and see its status.
struct OpenAIKeyView: View {
    @Environment(AppStore.self) private var store
    @State private var key = ""
    @State private var error: String?

    var body: some View {
        let openAI = store.openAI
        Form {
            Section {
                LabeledContent("Status", value: openAI.configured ? (openAI.lastProblem == nil ? "Connected" : "Needs attention") : "Not set")
                    .accessibilityIdentifier("openai-status")
                if let problem = openAI.lastProblem { Text(problem).foregroundStyle(.secondary) }
            }
            if openAI.configured { AIActivitySection() }
            Section {
                SecureField(openAI.configured ? "Replace Key" : "API Key", text: $key)
                    .textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("openai-key-field")
                Button("Save") {
                    do { try openAI.save(key); key = ""; error = nil; store.organizeInBackground() }
                    catch { self.error = (error as? LocalizedError)?.errorDescription ?? "The key couldn’t be saved." }
                }
                .disabled(key.isEmpty)
                if let error { Text(error).foregroundStyle(.red) }
            } footer: {
                Text("Stored only in this device’s Keychain. Used to organize your channels, combine duplicate feeds and tidy channel, movie and show names with GPT-6 Luna, find games in the guide, and understand searches the app can’t match on its own. Only channel names in your regions and languages are sent, never stream addresses.")
            }
            if openAI.configured {
                Section { Button("Remove Key", role: .destructive) { try? openAI.remove() } }
            }
        }
        .navigationTitle("OpenAI")
    }
}

/// What the background AI jobs found, and what they're doing now.
private struct AIActivitySection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let summary = store.aiResults.summary
        Section {
            if let activity = store.aiActivity {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(activity).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ai-activity")
            } else {
                LabeledContent("Last Run") {
                    if let date = summary.lastRun { Text(date, format: .relative(presentation: .named)) } else { Text("Not yet") }
                }
                .accessibilityIdentifier("ai-last-run")
            }
            row("Games Found", summary.gamesFound, checked: summary.listingsChecked, noun: "listings")
            row("Feeds Combined", summary.feedsCombined, checked: summary.pairsChecked, noun: "pairs")
            row("Names Tidied", summary.namesTidied, checked: summary.namesChecked, noun: "names")
            if let usage = store.aiResults.usage, usage.requests > 0 {
                LabeledContent("Estimated Cost") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(usage.dollars.dollarText).monospacedDigit()
                        if let last = store.aiResults.lastRunUsage {
                            Text("Last run \(last.dollars.dollarText) · \(last.requests.formatted()) requests").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ai-cost")
            }
            let examples = store.aiResults.examples()
            if !examples.isEmpty {
                DisclosureGroup("What AI Changed") {
                    ForEach(examples, id: \.before) { example in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(example.before).font(.caption).foregroundStyle(.secondary).strikethrough()
                            Text(example.after).font(.subheadline)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityIdentifier("ai-examples")
            }
            Button("Check Now") { store.runAIJobs() }
                .disabled(store.aiActivity != nil || !store.catalogReady || store.demo)
                .accessibilityIdentifier("ai-run-now")
        } header: {
            Text("Activity")
        } footer: {
            Text("Runs after your lineup loads, when you open the app and after each refresh. Only new channels and listings are sent. The cost is estimated on this iPhone from the tokens each request used at GPT-6 Luna’s published prices; your OpenAI bill is the record.")
        }
    }

    private func row(_ title: String, _ value: Int, checked: Int, noun: String) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(value, format: .number).monospacedDigit()
                if checked > 0 { Text("of \(checked.formatted()) \(noun)").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
