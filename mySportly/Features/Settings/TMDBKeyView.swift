import SwiftUI

/// Settings → TMDB: paste, replace or remove the API Read Access Token, and see its status.
struct TMDBKeyView: View {
    @Environment(AppStore.self) private var store
    @State private var token = ""
    @State private var error: String?

    var body: some View {
        let tmdb = store.tmdb
        Form {
            Section {
                LabeledContent("Status", value: tmdb.configured ? (tmdb.lastProblem == nil ? "Connected" : "Needs attention") : "Not set")
                    .accessibilityIdentifier("tmdb-status")
                if let problem = tmdb.lastProblem { Text(problem).foregroundStyle(.secondary) }
            }
            Section {
                SecureField(tmdb.configured ? "Replace Token" : "API Read Access Token", text: $token)
                    .textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("tmdb-token-field")
                Button("Save") {
                    do { try tmdb.save(token); token = ""; error = nil }
                    catch { self.error = (error as? LocalizedError)?.errorDescription ?? "The token couldn’t be saved." }
                }
                .disabled(token.isEmpty)
                if let error { Text(error).foregroundStyle(.red) }
                if let settings = URL(string: "https://www.themoviedb.org/settings/api") { Link("Get a Token from TMDB", destination: settings) }
            } footer: {
                Text("Stored only in this device’s Keychain. Adds TMDB’s backdrops, title logos, ratings, cast, trailers and related titles in your library to movie and show pages. Only titles, years and TMDB ids are sent to TMDB, never your provider’s name, addresses or sign-in.")
            }
            if tmdb.configured {
                Section { Button("Remove Token", role: .destructive) { try? tmdb.remove() } }
            }
        }
        .navigationTitle("TMDB")
    }
}
