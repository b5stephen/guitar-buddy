//
//  SongMarkerTests.swift
//  GuitarBuddyTests
//

import Foundation
import SwiftData
import Testing
@testable import GuitarBuddy

/// The storage rules for points and clips, and the time parsing behind the
/// editor's typed fields.
@MainActor
@Suite("Song markers")
struct SongMarkerTests {
    private let context: ModelContext
    private let song: SavedSong

    init() throws {
        context = ModelContext(try AppSchema.inMemoryContainer())
        song = SavedSong.save(
            songID: "i.1", title: "Little Wing", artistName: "Jimi Hendrix",
            artworkURL: nil, speed: 0.6, in: context
        )
    }

    private func allMarkers() throws -> [SongMarker] {
        try context.fetch(FetchDescriptor<SongMarker>())
    }

    @Test("A marker with only a start is a point; with an end it's a clip")
    func pointVersusClip() {
        let point = SongMarker.add(to: song, name: "Solo", startTime: 61, endTime: nil, in: context)
        let clip = SongMarker.add(to: song, name: "Riff", startTime: 10, endTime: 18.5, in: context)
        #expect(!point.isClip)
        #expect(clip.isClip)
        #expect(point.timeLabel == "1:01")
        #expect(clip.timeLabel == "0:10 – 0:18")
    }

    @Test("Blank names get a default that counts markers of the same kind")
    func defaultNames() {
        let a = SongMarker.add(to: song, name: "", startTime: 1, endTime: nil, in: context)
        let b = SongMarker.add(to: song, name: "  ", startTime: 2, endTime: nil, in: context)
        let c = SongMarker.add(to: song, name: "", startTime: 3, endTime: 8, in: context)
        #expect(a.name == "Marker 1")
        #expect(b.name == "Marker 2")
        #expect(c.name == "Clip 1")
    }

    @Test("An end too close to the start is dropped rather than making a zero-length clip")
    func rejectsTinyClip() {
        let marker = SongMarker.add(to: song, name: "x", startTime: 10, endTime: 10.2, in: context)
        #expect(marker.endTime == nil)
        marker.set(name: "x", start: 10, end: 9)
        #expect(marker.endTime == nil)
        marker.set(name: "x", start: 10, end: 10.5)
        #expect(marker.endTime == 10.5)
    }

    @Test("Clearing the end turns a clip back into a point")
    func clearEnd() {
        let marker = SongMarker.add(to: song, name: "Riff", startTime: 10, endTime: 18, in: context)
        marker.clearEnd(in: context)
        #expect(!marker.isClip)
        #expect(marker.startTime == 10)
    }

    @Test("Markers sort by where they fall in the track")
    func sortedByStart() {
        SongMarker.add(to: song, name: "C", startTime: 90, endTime: nil, in: context)
        SongMarker.add(to: song, name: "A", startTime: 5, endTime: nil, in: context)
        SongMarker.add(to: song, name: "B", startTime: 40, endTime: 50, in: context)
        #expect(song.sortedMarkers.map(\.name) == ["A", "B", "C"])
    }

    @Test("Deleting a marker leaves the others alone")
    func deleteOne() throws {
        let keep = SongMarker.add(to: song, name: "Keep", startTime: 1, endTime: nil, in: context)
        let drop = SongMarker.add(to: song, name: "Drop", startTime: 2, endTime: nil, in: context)
        SongMarker.delete(drop, in: context)
        let remaining = try allMarkers()
        #expect(remaining.count == 1)
        #expect(remaining[0].persistentModelID == keep.persistentModelID)
    }

    @Test("Deleting a song takes its markers with it")
    func cascadeDelete() throws {
        SongMarker.add(to: song, name: "Riff", startTime: 10, endTime: 18, in: context)
        context.delete(song)
        try context.save()
        #expect(try allMarkers().isEmpty)
    }

    @Test("Precise times format to tenths and parse back")
    func preciseTimeRoundTrip() {
        #expect(PreciseTime.format(63.4) == "1:03.4")
        #expect(PreciseTime.format(0) == "0:00.0")
        #expect(PreciseTime.format(3723.05) == "1:02:03.1")
        #expect(PreciseTime.parse("1:03.4") == 63.4)
        #expect(PreciseTime.parse("1:03") == 63)
        #expect(PreciseTime.parse("83.4") == 83.4)
        #expect(PreciseTime.parse("1:02:03.1") == 3723.1)
        #expect(PreciseTime.parse("") == nil)
        #expect(PreciseTime.parse("1:x") == nil)
        #expect(PreciseTime.parse("-5") == nil)
    }

    @Test("Tick spacing keeps to a handful of labels at every zoom")
    func tickInterval() {
        #expect(MarkerRangeEditor.tickInterval(for: 5) == 1)
        #expect(MarkerRangeEditor.tickInterval(for: 30) == 5)
        #expect(MarkerRangeEditor.tickInterval(for: 245) == 60)
    }
}
