//
//  GuitarBuddyTests.swift
//  GuitarBuddyTests
//
//  Created by Stephen Denekamp on 05/09/2026.
//

import Foundation
import SwiftData
import Testing
@testable import GuitarBuddy

/// The storage rules behind the saved list. These are the parts of the feature
/// worth testing: the views need a simulator and `SongLookup` needs a real
/// Apple Music entitlement, but getting the upsert wrong here silently
/// destroys speeds the user tuned by hand.
@MainActor
@Suite("Saved songs")
struct SavedSongTests {
    /// A fresh in-memory store per test, so nothing leaks between them.
    private let context: ModelContext

    init() throws {
        context = ModelContext(try AppSchema.inMemoryContainer())
    }

    private func allSongs() throws -> [SavedSong] {
        try context.fetch(FetchDescriptor<SavedSong>())
    }

    @discardableResult
    private func save(
        _ songID: String,
        title: String = "Blackbird",
        artist: String = "The Beatles",
        artworkURL: URL? = nil,
        speed: Double = 1.0
    ) -> SavedSong {
        SavedSong.save(
            songID: songID,
            title: title,
            artistName: artist,
            artworkURL: artworkURL,
            speed: speed,
            in: context
        )
    }

    @Test("Saving a new song stores every field")
    func savesNewSong() throws {
        let url = URL(string: "https://example.com/art.jpg")!
        save("i.1", title: "Little Wing", artist: "Jimi Hendrix", artworkURL: url, speed: 0.6)

        let songs = try allSongs()
        #expect(songs.count == 1)
        #expect(songs[0].songID == "i.1")
        #expect(songs[0].title == "Little Wing")
        #expect(songs[0].artistName == "Jimi Hendrix")
        #expect(songs[0].artworkURL == url)
        #expect(songs[0].speed == 0.6)
    }

    @Test("Re-saving the same song updates it instead of duplicating")
    func reSaveUpdatesInPlace() throws {
        save("i.1", speed: 1.0)
        save("i.1", speed: 0.5)

        let songs = try allSongs()
        #expect(songs.count == 1)
        #expect(songs[0].speed == 0.5)
    }

    @Test("Re-saving refreshes metadata that has gone stale")
    func reSaveRefreshesMetadata() throws {
        let old = URL(string: "https://example.com/old.jpg")!
        let new = URL(string: "https://example.com/new.jpg")!
        save("i.1", title: "Blackbrid", artist: "Beatles", artworkURL: old)
        save("i.1", title: "Blackbird", artist: "The Beatles", artworkURL: new)

        let song = try #require(SavedSong.find(songID: "i.1", in: context))
        #expect(song.title == "Blackbird")
        #expect(song.artistName == "The Beatles")
        #expect(song.artworkURL == new)
    }

    /// The rule behind `SavedSongsView.add`: re-adding a song the user has
    /// already tuned must not throw away the speed they set.
    @Test("Adding an already-saved song keeps its tuned speed")
    func addingExistingSongKeepsSpeed() throws {
        save("i.1", speed: 0.6)

        // What the add path does when the song is already on the list.
        let existing = try #require(SavedSong.find(songID: "i.1", in: context))
        SavedSong.touch(existing, in: context)

        let songs = try allSongs()
        #expect(songs.count == 1)
        #expect(songs[0].speed == 0.6)
    }

    @Test("Finding a song by ID")
    func findsByID() {
        save("i.1")
        #expect(SavedSong.find(songID: "i.1", in: context) != nil)
        #expect(SavedSong.find(songID: "i.2", in: context) == nil)
    }

    @Test("The list sorts most recently practised first")
    func sortsByLastPracticed() throws {
        // Explicit dates rather than three saves in a row: the clock may not
        // tick between them, and a tie makes the expected order arbitrary.
        save("i.1", title: "First").lastPracticed = .now.addingTimeInterval(-300)
        save("i.2", title: "Second").lastPracticed = .now.addingTimeInterval(-200)
        save("i.3", title: "Third").lastPracticed = .now.addingTimeInterval(-100)

        // Practising the oldest again should move it to the top.
        let first = try #require(SavedSong.find(songID: "i.1", in: context))
        SavedSong.touch(first, in: context)

        let descriptor = FetchDescriptor<SavedSong>(
            sortBy: [SortDescriptor(\.lastPracticed, order: .reverse)]
        )
        let ordered = try context.fetch(descriptor)
        #expect(ordered.map(\.songID) == ["i.1", "i.3", "i.2"])
    }

    @Test("Deleting removes only the song asked for")
    func deleteRemovesOne() throws {
        save("i.1")
        save("i.2")

        context.delete(try #require(SavedSong.find(songID: "i.1", in: context)))
        try context.save()

        let songs = try allSongs()
        #expect(songs.count == 1)
        #expect(songs[0].songID == "i.2")
    }

    @Test("Percent rounds the stored speed for display")
    func percentRounds() {
        #expect(save("i.1", speed: 0.755).percent == 76)
        #expect(save("i.2", speed: 1.0).percent == 100)
    }
}
