//
//  LoopChainTests.swift
//  MusicMomentumTests
//

import Foundation
import SwiftData
import Testing
@testable import MusicMomentum

/// Tested against `Loop.step` rather than the controller, so nothing here
/// needs a music player.
@MainActor
@Suite("Loop chains")
struct LoopChainTests {
    private let context: ModelContext
    private let song: SavedSong

    init() throws {
        context = ModelContext(try AppSchema.inMemoryContainer())
        song = SavedSong.save(
            songID: "i.1", title: "Little Wing", artistName: "Jimi Hendrix",
            artworkData: nil, speed: 0.6, in: context
        )
    }

    private func chain(_ ranges: [(TimeInterval, TimeInterval)]) -> [Loop.Segment] {
        ranges.map { start, end in
            let marker = SongMarker.add(to: song, name: "", startTime: start, endTime: end, in: context)
            return .init(markerID: marker.persistentModelID, start: start, end: end)
        }
    }

    private func step(
        _ segments: [Loop.Segment],
        at time: TimeInterval,
        current: Int?
    ) -> Loop.Step {
        Loop.step(segments: segments, time: time, current: current)
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
        // A seek here would be an audible hiccup at a seam the track plays fine.
        #expect(step(verseChorus, at: 20, current: 0) == .inside(1))
    }

    @Test("Outside the chain with nowhere to have come from, the playhead is left alone")
    func waitsAfterAJump() {
        let verseChorus = chain([(10, 20), (40, 55)])
        // Without the wait, sitting past a clip's end would read as "that clip
        // just finished" and the playhead could never leave.
        #expect(step(verseChorus, at: 200, current: nil) == .wait)
        #expect(step(verseChorus, at: 5, current: nil) == .wait)
        #expect(step(verseChorus, at: 30, current: 1) == .wait)
    }

    @Test("A clip index left over from a longer chain is ignored")
    func toleratesAStaleIndex() {
        let verseChorus = chain([(10, 20), (40, 55)])
        #expect(step(verseChorus, at: 200, current: 7) == .wait)
        #expect(step([], at: 12, current: 0) == .wait)
    }
}
