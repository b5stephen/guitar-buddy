//
//  SongPickerView.swift
//  MusicMomentum
//
//  NOTE: The project brief calls for the `.musicPicker` SwiftUI modifier, which
//  still doesn't exist in the iOS 26.5 SDK this project builds against (nothing
//  named `musicPicker` appears anywhere in MusicKit, and MusicKit ships no
//  SwiftUI views beyond `ArtworkImage`). This view stands in for it: one sheet
//  that searches the Apple Music catalog and both searches *and* browses the
//  user's own library. Swap it out for `.musicPicker` if and when the modifier
//  ships — `ContentView` only needs a `Song?` back either way.
//

import MusicKit
import SwiftData
import SwiftUI

struct SongPickerView: View {
    /// Called with the song the user taps; the sheet dismisses itself
    /// afterwards. A closure rather than a binding because callers do different
    /// things with the result — the practice screen plays it, the saved list
    /// saves it.
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
                    // No term yet, so there's nothing to search — offer the
                    // library itself instead of an empty "type something" page.
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
                            // The album is what tells four recordings of the
                            // same song apart, which is most of what a search
                            // for a well-covered song comes back with.
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
                    Button("Cancel") { dismiss() }
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

    /// Debounced search across whichever source is selected.
    private func runSearch() async {
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            searchError = nil
            return
        }

        // Let fast typing coalesce; cancellation here just skips the request.
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

    /// Combined identity so `.task(id:)` restarts on either input changing.
    private struct SearchKey: Equatable {
        let term: String
        let scope: SearchScope
    }
}

/// What the picker says when it has no list to show. All three say the same
/// thing about the other source, since the two scopes are the sheet's only real
/// choice and every one of these states is a reason to try the other one.
private struct SearchMessage: View {
    enum Kind {
        /// The catalog before anything is typed. The library has no equivalent:
        /// it can be browsed, so it never has to wait for a term.
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

/// Shared with `LibraryBrowseView`, which lists songs the same way.
struct SongRow: View {
    let song: Song
    /// Names the album after the artist. Off where the list is already one
    /// album's worth of songs and saying so on every row tells the user
    /// nothing.
    var showsAlbum = false

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = song.artwork {
                ArtworkImage(artwork, width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 48, height: 48)
                    .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        guard showsAlbum, let album = song.albumTitle, !album.isEmpty else {
            return song.artistName
        }
        return "\(song.artistName) — \(album)"
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
