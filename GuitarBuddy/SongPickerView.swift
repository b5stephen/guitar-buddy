//
//  SongPickerView.swift
//  GuitarBuddy
//
//  NOTE: The project brief calls for the `.musicPicker` SwiftUI modifier, which
//  is not present in the iOS 26.2 SDK this project builds against (nothing
//  named `musicPicker` exists in MusicKit or its SwiftUI overlay). This view
//  stands in for it: one sheet that searches both the Apple Music catalog and
//  the user's personal library. Swap it out for `.musicPicker` if and when the
//  modifier ships — `ContentView` only needs a `Song?` back either way.
//

import MusicKit
import SwiftUI

struct SongPickerView: View {
    /// Set when the user taps a row; the sheet dismisses itself afterwards.
    @Binding var selection: Song?

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
                    ContentUnavailableView(
                        "Search failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(searchError)
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: searchTerm)
                        .opacity(searchTerm.isEmpty ? 0 : 1)
                        .overlay {
                            if searchTerm.isEmpty {
                                ContentUnavailableView(
                                    "Find a song",
                                    systemImage: "magnifyingglass",
                                    description: Text("Search \(scope.rawValue) for something to practice.")
                                )
                            }
                        }
                } else {
                    List(results) { song in
                        Button {
                            selection = song
                            dismiss()
                        } label: {
                            SongRow(song: song)
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

private struct SongRow: View {
    let song: Song

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
                Text(song.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
