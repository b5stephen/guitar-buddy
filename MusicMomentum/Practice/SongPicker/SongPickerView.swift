//
//  SongPickerView.swift
//  MusicMomentum
//
//  Stands in for a `.musicPicker` modifier MusicKit doesn't ship (as of the
//  iOS 26.5 SDK it has no SwiftUI views beyond `ArtworkImage`).
//

import MusicKit
import SwiftData
import SwiftUI

struct SongPickerView: View {
    let onSelect: (Song) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchTerm = ""
    @State private var scope: SearchScope = .library
    @State private var results: MusicItemCollection<Song> = []
    @State private var isSearching = false
    @State private var searchError: String?

    enum SearchScope: String, CaseIterable, Identifiable {
        case library = "My Library"
        case catalog = "Apple Music"
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let searchError {
                    SearchMessage(kind: .failed(searchError))
                } else if searchTerm.isEmpty, scope == .library {
                    LibraryBrowseView { song in
                        onSelect(song)
                        dismiss()
                    }
                } else if searchTerm.isEmpty {
                    SearchMessage(kind: .prompt)
                } else if results.isEmpty {
                    SearchMessage(kind: .noResults(searchTerm))
                } else {
                    List(results) { song in
                        Button {
                            onSelect(song)
                            dismiss()
                        } label: {
                            // The album is what tells recordings of one song apart.
                            SongRow(song: song, showsAlbum: true)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Choose Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                if isSearching {
                    ToolbarItem(placement: .confirmationAction) { ProgressView() }
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Source", selection: $scope) {
                    ForEach(SearchScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .searchable(text: $searchTerm, prompt: "Songs, artists, albums")
            .task(id: SearchKey(term: searchTerm, scope: scope)) {
                await runSearch()
            }
        }
    }

    private func runSearch() async {
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            searchError = nil
            return
        }

        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }

        do {
            switch scope {
            case .catalog:
                var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
                request.limit = 25
                results = try await request.response().songs
            case .library:
                var request = MusicLibrarySearchRequest(term: term, types: [Song.self])
                request.limit = 25
                results = try await request.response().songs
            }
            searchError = nil
        } catch is CancellationError {
            return
        } catch {
            results = []
            searchError = error.localizedDescription
        }
    }

    private struct SearchKey: Equatable {
        let term: String
        let scope: SearchScope
    }
}

private struct SearchMessage: View {
    enum Kind {
        /// Catalog only; the library is browsed instead.
        case prompt
        case noResults(String)
        case failed(String)
    }

    let kind: Kind

    var body: some View {
        switch kind {
        case .prompt:
            ContentUnavailableView(
                "Search Apple Music",
                systemImage: "magnifyingglass",
                description: Text("Or switch to My Library to browse what you already own.")
            )
        case .noResults(let term):
            ContentUnavailableView(
                "No results for \u{201C}\(term)\u{201D}",
                systemImage: "magnifyingglass",
                description: Text("Check the spelling, or try the other source.")
            )
        case .failed(let reason):
            ContentUnavailableView(
                "Search couldn't finish",
                systemImage: "exclamationmark.triangle",
                description: Text(reason)
            )
        }
    }
}

// MARK: - Previews

#Preview("Browsing") {
    SongPickerView { _ in }
        .modelContainer(try! AppSchema.inMemoryContainer())
}

#Preview("Nothing typed") {
    SearchMessage(kind: .prompt)
}

#Preview("No results") {
    SearchMessage(kind: .noResults("blakbird"))
}

#Preview("Search failed") {
    SearchMessage(kind: .failed("The Internet connection appears to be offline."))
}
