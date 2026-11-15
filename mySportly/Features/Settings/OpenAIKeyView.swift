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
                Text("Stored only in this device’s Keychain. Used to sort channel groups, combine duplicate feeds, find games in the guide, tidy channel names and understand searches the app can’t match on its own.")
            }
            if openAI.configured {
                Section { Button("Remove Key", role: .destructive) { try? openAI.remove() } }
            }
        }
        .navigationTitle("OpenAI")
    }
}
