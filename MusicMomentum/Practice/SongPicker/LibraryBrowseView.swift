//
//  LibraryBrowseView.swift
//  MusicMomentum
//
//  `MusicLibrarySearchRequest` needs a term; `MusicLibraryRequest` returns the
//  library itself, so the user can drill artist → album → song without typing.
//

import MusicKit
import SwiftData
import SwiftUI

struct LibraryBrowseView: View {
    let onSelect: (Song) -> Void

    @Query(sort: \SavedSong.lastPracticed, order: .reverse)
    private var saved: [SavedSong]

    @State private var openingID: String?
    @State private var missingID: String?

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
            // Music videos are greyed out rather than hidden so track numbers
            // don't appear to skip.
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

/// Loads a `MusicItemCollection` a batch at a time, and owns the loading,
/// empty and failure states.
private struct PagedLibraryList<Item: MusicItem & Identifiable, Row: View>: View {
    let title: String
    /// Plural, lower case: "Couldn't load your albums".
    let shelf: String
    let emptyTitle: String
    let emptyMessage: String
    let load: () async throws -> MusicItemCollection<Item>
    @ViewBuilder let row: (Item) -> Row

    /// `nil` until the first batch lands, as distinct from empty.
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
                            // Rows are built lazily, so this only fetches once
                            // the user scrolls to it.
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

/// Same metrics as the real rows, so nothing moves when content arrives.
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
