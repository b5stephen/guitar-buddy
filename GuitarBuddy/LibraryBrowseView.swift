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
import SwiftData
import SwiftUI

/// Root of the browse hierarchy: the four ways into a music library, and above
/// them the songs the user is already working on — the shortest way back to
/// yesterday's practice, which is what most visits here are after.
struct LibraryBrowseView: View {
    /// Called with the chosen song; the picker dismisses itself from there.
    let onSelect: (Song) -> Void

    @Query(sort: \SavedSong.lastPracticed, order: .reverse)
    private var saved: [SavedSong]

    /// The saved song being resolved back into a `Song`, and the one that
    /// couldn't be — a saved row can outlive its place in the library.
    @State private var openingID: String?
    @State private var missingID: String?

    /// Enough of the list to be worth offering, not so much that it buries the
    /// four shelves underneath it.
    private static let recentLimit = 3

    var body: some View {
        List {
            Section("Browse") {
                NavigationLink {
                    artistsList
                } label: {
                    ShelfRow(title: "Artists", systemImage: "music.microphone")
                }
                NavigationLink {
                    albumsList
                } label: {
                    ShelfRow(title: "Albums", systemImage: "square.stack")
                }
                NavigationLink {
                    playlistsList
                } label: {
                    ShelfRow(title: "Playlists", systemImage: "music.note.list")
                }
                NavigationLink {
                    songsList
                } label: {
                    ShelfRow(title: "Songs", systemImage: "music.note")
                }
            }

            if !recent.isEmpty {
                Section("Practising lately") {
                    ForEach(recent) { song in
                        Button {
                            practise(song)
                        } label: {
                            RecentRow(
                                song: song,
                                isLoading: openingID == song.songID,
                                isMissing: missingID == song.songID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var recent: [SavedSong] {
        Array(saved.prefix(Self.recentLimit))
    }

    /// The picker deals in `Song`s, and the saved list keeps only IDs, so a tap
    /// here is a lookup before it's a choice.
    private func practise(_ song: SavedSong) {
        openingID = song.songID
        missingID = nil
        Task {
            let found = try? await SongLookup.song(
                libraryID: song.songID,
                catalogID: song.catalogID
            )
            openingID = nil
            guard let found else {
                missingID = song.songID
                return
            }
            onSelect(found)
        }
    }

    private var artistsList: some View {
        PagedLibraryList(
            title: "Artists",
            shelf: "artists",
            emptyTitle: "No artists yet",
            emptyMessage: "Artists you add to your library on this Apple ID show up here."
        ) {
            var request = MusicLibraryRequest<Artist>()
            request.sort(by: \.name, ascending: true)
            return try await request.response().items
        } row: { artist in
            NavigationLink {
                albumsList(by: artist)
            } label: {
                ArtistRow(artist: artist)
            }
        }
    }

    private func albumsList(by artist: Artist) -> some View {
        PagedLibraryList(
            title: artist.name,
            shelf: "albums",
            emptyTitle: "No albums yet",
            emptyMessage: "Nothing by this artist is in your library on this Apple ID."
        ) {
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
        PagedLibraryList(
            title: "Albums",
            shelf: "albums",
            emptyTitle: "No albums yet",
            emptyMessage: "Albums you add to your library on this Apple ID show up here."
        ) {
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
        PagedLibraryList(
            title: "Playlists",
            shelf: "playlists",
            emptyTitle: "No playlists yet",
            emptyMessage: "Playlists you make or follow on this Apple ID show up here."
        ) {
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
        PagedLibraryList(
            title: "Songs",
            shelf: "songs",
            emptyTitle: "No songs yet",
            emptyMessage: "Songs you add to your library on this Apple ID show up here."
        ) {
            var request = MusicLibraryRequest<Song>()
            request.sort(by: \.title, ascending: true)
            return try await request.response().items
        } row: { song in
            Button {
                onSelect(song)
            } label: {
                SongRow(song: song, showsAlbum: true)
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
        PagedLibraryList(
            title: title,
            shelf: "tracks",
            emptyTitle: "No tracks here",
            emptyMessage: "This one has nothing in it to play.",
            load: load
        ) { track in
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

// MARK: - Shelf sizes

/// One of the four ways in. The icon is a tinted rounded square rather than a
/// bare symbol so the shelves read as destinations, not as settings.
private struct ShelfRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(.tint.opacity(0.15))
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tint)
                }
            Text(title)
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A saved song offered at the top of the browse root. Smaller artwork than a
/// result row, because this is a shortcut past the list rather than the list.
private struct RecentRow: View {
    let song: SavedSong
    let isLoading: Bool
    let isMissing: Bool

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .lineLimit(1)
                Text(isMissing ? "Not in your library any more" : song.artistName)
                    .font(.caption)
                    .foregroundStyle(isMissing ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(song.percent)%")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.tint)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var artwork: some View {
        if isLoading {
            placeholder { ProgressView() }
        } else if let artwork = song.artwork {
            ArtworkImage(artwork, width: 38, height: 38)
                .clipShape(.rect(cornerRadius: 6))
        } else {
            placeholder { Image(systemName: "music.note").foregroundStyle(.secondary) }
        }
    }

    private func placeholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.quaternary)
            .frame(width: 38, height: 38)
            .overlay(content())
    }
}

// MARK: - Paging

/// Loads a `MusicItemCollection` and extends it as the user reaches the bottom,
/// so a big library doesn't have to arrive in one request. Owns the loading,
/// empty and failure states so the four lists above don't each repeat them.
private struct PagedLibraryList<Item: MusicItem & Identifiable, Row: View>: View {
    let title: String
    /// What this list holds, in the plural and lower case, for the sentence a
    /// failure puts it in: "Couldn't load your albums".
    let shelf: String
    let emptyTitle: String
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
                ContentUnavailableView {
                    Label("Couldn't load your \(shelf)", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    // The request is the only thing that failed, and a library
                    // request usually fails for a reason that has passed by the
                    // time the user reads about it.
                    Button("Try Again") {
                        self.errorMessage = nil
                        Task { await loadFirstBatch() }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
            } else if let items {
                if items.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "music.note",
                        description: Text(emptyMessage)
                    )
                } else {
                    List {
                        ForEach(items) { row($0) }
                        if items.hasNextBatch {
                            // A `List` builds rows lazily, so this only appears
                            // — and only fetches — once the user scrolls to it.
                            // Ghost rows rather than a spinner, because what's
                            // arriving is more of the same list.
                            VStack(spacing: 12) {
                                SkeletonRow().opacity(0.5)
                                SkeletonRow().opacity(0.25)
                            }
                            .listRowSeparator(.hidden)
                            .task(id: items.count) { await loadMore() }
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                // The shape of the list it's about to be, rather than a spinner
                // in the middle of an empty screen: the wait reads as this list
                // filling in.
                List(0..<5, id: \.self) { index in
                    SkeletonRow()
                        .opacity(1 - Double(index) * 0.18)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .allowsHitTesting(false)
                .accessibilityLabel("Loading \(shelf)")
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

/// A row with nothing in it yet: artwork and two lines of text, in the metrics
/// the real rows use, so nothing moves when the content arrives.
private struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 7) {
                bar(span: 6)
                bar(span: 4)
                    .opacity(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func bar(span: Int) -> some View {
        Capsule()
            .fill(.quaternary)
            .frame(height: 11)
            .containerRelativeFrame(.horizontal, count: 10, span: span, spacing: 0)
    }
}

// MARK: - Rows

private struct ArtistRow: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: 12) {
            // Artwork here is whatever the library happens to hold for an
            // artist, which is often nothing — but a text-only row next to the
            // album and song rows is what makes the browse levels look
            // half-built.
            LibraryArtwork(artwork: artist.artwork, fallback: "music.microphone")
            Text(artist.name).lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

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
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            LibraryArtwork(artwork: playlist.artwork, fallback: "music.note.list")
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name).lineLimit(1)
                if let curator = playlist.curatorName, !curator.isEmpty {
                    Text(curator)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
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

// MARK: - Previews

#Preview("Browse root") {
    let container = try! AppSchema.inMemoryContainer()
    SavedSong.save(
        songID: "1", title: "Little Wing", artistName: "Jimi Hendrix",
        artworkData: nil, speed: 0.6, in: ModelContext(container)
    )
    return NavigationStack {
        LibraryBrowseView { _ in }
            .navigationTitle("Choose Song")
            .navigationBarTitleDisplayMode(.inline)
    }
    .modelContainer(container)
}

/// The three states of a browse level, driven through the real view by a load
/// that hangs, comes back empty, or fails.
private func albumsPreview(
    load: @escaping () async throws -> MusicItemCollection<Album>
) -> some View {
    NavigationStack {
        PagedLibraryList(
            title: "Albums",
            shelf: "albums",
            emptyTitle: "No albums yet",
            emptyMessage: "Albums you add to your library on this Apple ID show up here.",
            load: load
        ) { album in
            AlbumRow(album: album)
        }
    }
}

#Preview("Loading") {
    albumsPreview {
        try await Task.sleep(for: .seconds(600))
        return []
    }
}

#Preview("Empty") {
    albumsPreview { [] }
}

#Preview("Failed") {
    albumsPreview { throw URLError(.notConnectedToInternet) }
}
