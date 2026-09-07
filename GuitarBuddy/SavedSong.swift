//
//  SavedSong.swift
//  GuitarBuddy
//

import Foundation
import MusicKit
import SwiftData

/// A song the user has put on their practice list, along with the speed they
/// practice it at.
///
/// `songID` stores MusicKit's `MusicItemID` raw value (a `String`) rather than
/// the `Song` struct itself, since `Song` isn't a SwiftData-storable type. The
/// title, artist and artwork are copied in alongside it so the saved list can
/// be drawn without asking Apple Music for anything.
@Model
final class SavedSong {
    #Unique<SavedSong>([\.songID])

    var songID: String = ""
    var speed: Double = 1.0
    var title: String = ""
    var artistName: String = ""
    var artworkURL: URL?
    /// Last time the user did something with this song — saved it, changed its
    /// speed, or loaded it to practice. The saved list sorts on it.
    var lastPracticed: Date = Date.now

    init(
        songID: String,
        speed: Double,
        title: String = "",
        artistName: String = "",
        artworkURL: URL? = nil,
        lastPracticed: Date = .now
    ) {
        self.songID = songID
        self.speed = speed
        self.title = title
        self.artistName = artistName
        self.artworkURL = artworkURL
        self.lastPracticed = lastPracticed
    }

    var percent: Int { Int((speed * 100).rounded()) }
}

// MARK: - Storage

extension SavedSong {
    /// The one saved song with this ID, if it's on the list. `#Unique` above
    /// guarantees there's never more than one.
    static func find(songID: String, in context: ModelContext) -> SavedSong? {
        let descriptor = FetchDescriptor<SavedSong>(
            predicate: #Predicate { $0.songID == songID }
        )
        return try? context.fetch(descriptor).first
    }

    /// Adds a song to the list, or updates the one that's already there.
    ///
    /// Takes plain values rather than a `Song` so the storage rules can be
    /// tested — MusicKit's `Song` has no public initialiser, so a test can't
    /// make one. `save(song:speed:in:)` below is the call the app makes.
    @discardableResult
    static func save(
        songID: String,
        title: String,
        artistName: String,
        artworkURL: URL?,
        speed: Double,
        in context: ModelContext
    ) -> SavedSong {
        let song: SavedSong
        if let existing = find(songID: songID, in: context) {
            existing.speed = speed
            // Metadata can go stale — a track gets retitled, artwork is
            // replaced — so re-saving refreshes it rather than trusting the
            // copy taken the first time.
            existing.title = title
            existing.artistName = artistName
            existing.artworkURL = artworkURL
            song = existing
        } else {
            song = SavedSong(
                songID: songID,
                speed: speed,
                title: title,
                artistName: artistName,
                artworkURL: artworkURL
            )
            context.insert(song)
        }
        song.lastPracticed = .now
        try? context.save()
        return song
    }

    /// Saves a MusicKit song at `speed`.
    @discardableResult
    static func save(song: Song, speed: Double, in context: ModelContext) -> SavedSong {
        save(
            songID: song.id.rawValue,
            title: song.title,
            artistName: song.artistName,
            // 160px covers a 48pt row at @3x.
            artworkURL: song.artwork?.url(width: 160, height: 160),
            speed: speed,
            in: context
        )
    }

    /// Moves a song to the top of the list without otherwise touching it.
    static func touch(_ song: SavedSong, in context: ModelContext) {
        song.lastPracticed = .now
        try? context.save()
    }
}

// MARK: - Schema

/// Every model the app stores, in one place: the app, the previews and the
/// tests all build their containers from this, so adding a model is a one-line
/// edit rather than a hunt for the places that list them.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [SavedSong.self]

    /// A throwaway container for previews and tests. Nothing it holds outlives
    /// the process.
    static func inMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
