//
//  LibraryBrowseView.swift
//  GuitarBuddy
//
//  Browsing, as opposed to searching. `MusicLibrarySearchRequest` needs a term
//  before it returns anything, so the picker used to demand that the user
//  already know what they wanted. `MusicLibraryRequest` returns the library
//  itself, which lets them drill artist → album → song without typing.
//

import MusicKit
import SwiftUI

/// Root of the browse hierarchy: the four ways into a music library.
struct LibraryBrowseView: View {
    /// Called with the chosen song; the picker dismisses itself from there.
    let onSelect: (Song) -> Void

    var body: some View {
        List {
            NavigationLink {
                artistsList
            } label: {
                Label("Artists", systemImage: "music.microphone")
            }
            NavigationLink {
                albumsList
            } label: {
                Label("Albums", systemImage: "square.stack")
            }
            NavigationLink {
                playlistsList
            } label: {
                Label("Playlists", systemImage: "music.note.list")
            }
            NavigationLink {
                songsList
            } label: {
                Label("Songs", systemImage: "music.note")
            }
        }
    }

    private var artistsList: some View {
        PagedLibraryList(title: "Artists", emptyMessage: "No artists in your library.") {
            var request = MusicLibraryRequest<Artist>()
            request.sort(by: \.name, ascending: true)
            return try await request.response().items
        } row: { artist in
            NavigationLink(artist.name) {
                albumsList(by: artist)
            }
        }
    }

    private func albumsList(by artist: Artist) -> some View {
        PagedLibraryList(title: artist.name, emptyMessage: "No albums by this artist.") {
            var request = MusicLibraryRequest<Album>()
            request.filter(matching: \.artists, contains: artist)
            request.sort(by: \.title, ascending: true)
            return try await request.response().items
        } row: { album in
            NavigationLink {
                trackList(of: album)
            } label: {
                AlbumRow(album: album)
            }
        }
    }

    private var albumsList: some View {
        PagedLibraryList(title: "Albums", emptyMessage: "No albums in your library.") {
            var request = MusicLibraryRequest<Album>()
            request.sort(by: \.title, ascending: true)
            return try await request.response().items
        } row: { album in
            NavigationLink {
                trackList(of: album)
            } label: {
                AlbumRow(album: album)
            }
        }
    }

    private var playlistsList: some View {
        PagedLibraryList(title: "Playlists", emptyMessage: "No playlists in your library.") {
            var request = MusicLibraryRequest<Playlist>()
            request.sort(by: \.name, ascending: true)
            return try await request.response().items
        } row: { playlist in
            NavigationLink {
                trackList(of: playlist)
            } label: {
                PlaylistRow(playlist: playlist)
            }
        }
    }

    private var songsList: some View {
        PagedLibraryList(title: "Songs", emptyMessage: "No songs in your library.") {
            var request = MusicLibraryRequest<Song>()
            request.sort(by: \.title, ascending: true)
            return try await request.response().items
        } row: { song in
            Button {
                onSelect(song)
            } label: {
                SongRow(song: song)
            }
            .buttonStyle(.plain)
        }
    }

    /// Album and playlist tracks arrive the same way — as a relationship that
    /// has to be asked for explicitly, from the library rather than the catalog.
    private func trackList(of album: Album) -> some View {
        trackList(title: album.title) {
            try await album.with([.tracks], preferredSource: .library).tracks ?? []
        }
    }

    private func trackList(of playlist: Playlist) -> some View {
        trackList(title: playlist.name) {
            try await playlist.with([.tracks], preferredSource: .library).tracks ?? []
        }
    }

    private func trackList(
        title: String,
        load: @escaping () async throws -> MusicItemCollection<Track>
    ) -> some View {
        PagedLibraryList(title: title, emptyMessage: "No tracks here.", load: load) { track in
            // Music videos live in the same track list but there's nothing to
            // practice along to, so they're shown greyed out rather than hidden
            // — otherwise the track numbers would appear to skip.
            Button {
                if case .song(let song) = track { onSelect(song) }
            } label: {
                TrackRow(track: track)
            }
            .buttonStyle(.plain)
            .disabled(!track.isSong)
        }
    }
}

// MARK: - Paging

/// Loads a `MusicItemCollection` and extends it as the user reaches the bottom,
/// so a big library doesn't have to arrive in one request. Owns the loading,
/// empty and failure states so the four lists above don't each repeat them.
private struct PagedLibraryList<Item: MusicItem & Identifiable, Row: View>: View {
    let title: String
    let emptyMessage: String
    let load: () async throws -> MusicItemCollection<Item>
    @ViewBuilder let row: (Item) -> Row

    /// `nil` until the first batch lands, which is what distinguishes "still
    /// loading" from "the library really is empty".
    @State private var items: MusicItemCollection<Item>?
    @State private var errorMessage: String?
    @State private var isLoadingMore = false

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView(
                    "Couldn't load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if let items {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Nothing here",
                        systemImage: "music.note",
                        description: Text(emptyMessage)
                    )
                } else {
                    List {
                        ForEach(items) { row($0) }
                        if items.hasNextBatch {
                            // A `List` builds rows lazily, so this only appears
                            // — and only fetches — once the user scrolls to it.
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                                .task(id: items.count) { await loadMore() }
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadFirstBatch() }
    }

    private func loadFirstBatch() async {
        guard items == nil else { return }
        do {
            items = try await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let current = items, current.hasNextBatch, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            if let next = try await current.nextBatch() {
                items? += next
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Rows

private struct AlbumRow: View {
    let album: Album

    var body: some View {
        HStack(spacing: 12) {
            LibraryArtwork(artwork: album.artwork, fallback: "square.stack")
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title).lineLimit(1)
                Text(album.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            LibraryArtwork(artwork: playlist.artwork, fallback: "music.note.list")
            Text(playlist.name).lineLimit(1)
        }
    }
}

private struct TrackRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            LibraryArtwork(artwork: track.artwork, fallback: "music.note")
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).lineLimit(1)
                Text(track.isSong ? track.artistName : "Music video")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Artwork at list-row size, or a placeholder when the item has none.
private struct LibraryArtwork: View {
    let artwork: Artwork?
    let fallback: String

    var body: some View {
        if let artwork {
            ArtworkImage(artwork, width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 48, height: 48)
                .overlay { Image(systemName: fallback).foregroundStyle(.secondary) }
        }
    }
}

private extension Track {
    var isSong: Bool {
        if case .song = self { return true }
        return false
    }
}
