//
//  LoopChainTests.swift
//  GuitarBuddyTests
//

import Foundation
import SwiftData
import Testing
@testable import GuitarBuddy

/// The rules a clip chain follows as the playhead moves through it: which clip
/// it's in, when to send it to the next, and when to leave it alone. Tested
/// against `Loop.step` rather than the controller, so none of it needs a music
/// player to be running.
@MainActor
@Suite("Loop chains")
struct LoopChainTests {
    private let context: ModelContext
    private let song: SavedSong

    init() throws {
        context = ModelContext(try AppSchema.inMemoryContainer())
        song = SavedSong.save(
            songID: "i.1", title: "Little Wing", artistName: "Jimi Hendrix",
            artworkURL: nil, speed: 0.6, in: context
        )
    }

    /// A chain built from real markers, since a segment is keyed by one.
    private func chain(_ ranges: [(TimeInterval, TimeInterval)]) -> [PlaybackController.Loop.Segment] {
        ranges.map { start, end in
            let marker = SongMarker.add(to: song, name: "", startTime: start, endTime: end, in: context)
            return .init(markerID: marker.persistentModelID, start: start, end: end)
        }
    }

    private func step(
        _ segments: [PlaybackController.Loop.Segment],
        at time: TimeInterval,
        current: Int?
    ) -> PlaybackController.Loop.Step {
        PlaybackController.Loop.step(segments: segments, time: time, current: current)
    }

    @Test("The playhead inside a clip reports that clip")
    func insideAClip() {
        let verseChorus = chain([(10, 20), (40, 55)])
        #expect(step(verseChorus, at: 12, current: nil) == .inside(0))
        #expect(step(verseChorus, at: 54, current: 0) == .inside(1))
    }

    @Test("Running off the end of a clip goes to the next one")
    func advancesToNextClip() {
        let verseChorus = chain([(10, 20), (40, 55)])
        #expect(step(verseChorus, at: 20, current: 0) == .jump(to: 1))
    }

    @Test("Running off the end of the last clip wraps back to the first")
    func wrapsAtTheEnd() {
        let verseChorus = chain([(10, 20), (40, 55)])
        #expect(step(verseChorus, at: 55.2, current: 1) == .jump(to: 0))
    }

    @Test("A single clip loops back on itself")
    func singleClipRepeats() {
        let solo = chain([(96, 128)])
        #expect(step(solo, at: 128, current: 0) == .jump(to: 0))
        #expect(step(solo, at: 100, current: 0) == .inside(0))
    }

    @Test("Clips butted end to end hand over without a seek")
    func contiguousClipsDoNotSeek() {
        let verseChorus = chain([(10, 20), (20, 35)])
        // The playhead has simply walked into the second clip, so there's
        // nothing to jump — a seek here would be an audible hiccup at a seam
        // the track plays perfectly well on its own.
        #expect(step(verseChorus, at: 20, current: 0) == .inside(1))
    }

    @Test("Outside the chain with nowhere to have come from, the playhead is left alone")
    func waitsAfterAJump() {
        let verseChorus = chain([(10, 20), (40, 55)])
        // What a jump to a point past the chain looks like: without the wait,
        // sitting beyond a clip's end would read as "that clip just finished"
        // and the playhead would be yanked back, unable to leave.
        #expect(step(verseChorus, at: 200, current: nil) == .wait)
        #expect(step(verseChorus, at: 5, current: nil) == .wait)
        // Between clips, still short of the next one: nothing to do yet.
        #expect(step(verseChorus, at: 30, current: 1) == .wait)
    }

    @Test("A clip index left over from a longer chain is ignored")
    func toleratesAStaleIndex() {
        let verseChorus = chain([(10, 20), (40, 55)])
        #expect(step(verseChorus, at: 200, current: 7) == .wait)
        #expect(step([], at: 12, current: 0) == .wait)
    }
}
