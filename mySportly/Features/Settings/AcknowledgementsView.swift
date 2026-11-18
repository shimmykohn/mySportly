import SwiftUI

/// The open-source software that plays MKV and other files, with the
/// licence texts and source links its licences ask the app to carry, and
/// TMDB's attribution.
struct AcknowledgementsView: View {
    private struct Component: Identifiable {
        let name: String, licence: String, source: String, files: [String]
        var id: String { name }
    }
    // Sources point at the exact versions this build links.
    private let components = [
        Component(name: "AetherEngine", licence: "LGPL 3.0 with an App Store exception · © Vincent Herbst",
                  source: "https://github.com/superuser404notfound/AetherEngine/tree/7.68.0", files: ["License-AetherEngine"]),
        Component(name: "FFmpeg", licence: "LGPL 2.1 or later · © the FFmpeg developers",
                  source: "https://github.com/superuser404notfound/FFmpegBuild/tree/3.15.0", files: ["License-LGPL-2.1"]),
        Component(name: "dav1d", licence: "BSD 2-Clause · © VideoLAN and dav1d authors",
                  source: "https://github.com/superuser404notfound/FFmpegBuild/tree/3.15.0", files: ["License-dav1d"]),
        Component(name: "zimg", licence: "WTFPL",
                  source: "https://github.com/superuser404notfound/FFmpegBuild/tree/3.15.0", files: ["License-zimg"]),
        Component(name: "libzvbi", licence: "LGPL 2.0 or later; ure.c MIT",
                  source: "https://github.com/superuser404notfound/FFmpegBuild/tree/3.15.0", files: ["License-LGPL-2.1", "License-libzvbi-ure"]),
        Component(name: "libdovi", licence: "MIT · © quietvoid and contributors",
                  source: "https://github.com/superuser404notfound/LibDovi/tree/2.2.0", files: ["License-libdovi"]),
        Component(name: "Anime4K", licence: "MIT · © 2019–2021 bloc97",
                  source: "https://github.com/bloc97/Anime4K", files: ["License-Anime4K"])
    ]

    var body: some View {
        List {
            Section {
                ForEach(components) { component in
                    NavigationLink {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if let source = URL(string: component.source) { Link("Source Code", destination: source) }
                                ForEach(component.files, id: \.self) { Text(Self.text($0)).font(.caption.monospaced()).textSelection(.enabled) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                        }
                        .navigationTitle(component.name).toolbarTitleDisplayMode(.inline)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(component.name)
                            Text(component.licence).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("mySportly plays MKV and other files with AetherEngine and FFmpeg. FFmpeg and its companion libraries are included as separate, replaceable frameworks under the LGPL.")
            }
            // TMDB asks apps that use its API to show this notice.
            Section {
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .accessibilityIdentifier("tmdb-attribution")
                if let site = URL(string: "https://www.themoviedb.org") { Link("themoviedb.org", destination: site) }
            } header: {
                Text("The Movie Database (TMDB)")
            } footer: {
                Text("With your own token (Settings → TMDB), movie and show pages show TMDB’s artwork, ratings, cast, trailers and recommendations.")
            }
        }
        .navigationTitle("Acknowledgements")
    }

    private static func text(_ file: String) -> String {
        Bundle.main.url(forResource: file, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }
}
