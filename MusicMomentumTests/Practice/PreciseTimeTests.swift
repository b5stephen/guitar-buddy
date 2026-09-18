//
//  PreciseTimeTests.swift
//  MusicMomentumTests
//

import Foundation
import Testing
@testable import MusicMomentum

/// A wrong parse places the marker somewhere else in the song without any
/// error, so every accepted shape is pinned here.
@Suite("Precise times")
struct PreciseTimeTests {
    @Test("Formats to tenths, hours only when needed", arguments: [
        (0.0, "0:00.0"),
        (63.4, "1:03.4"),
        (63.46, "1:03.5"),
        (599.96, "10:00.0"),
        (3661.2, "1:01:01.2"),
    ])
    func formats(seconds: TimeInterval, text: String) {
        #expect(PreciseTime.format(seconds) == text)
    }

    @Test("Parses every shape the field shows", arguments: [
        ("1:03.4", 63.4),
        ("1:03", 63.0),
        ("1:01:01.2", 3661.2),
        ("45", 45.0),
        ("  0:07.5 ", 7.5),
    ])
    func parses(text: String, seconds: TimeInterval) {
        #expect(PreciseTime.parse(text) == seconds)
    }

    @Test("Rejects anything it can't place", arguments: [
        "", "abc", "1:", "-5", "1:-3", "1:2:3:4", "1:x"
    ])
    func rejects(text: String) {
        #expect(PreciseTime.parse(text) == nil)
    }

    @Test("Formatting then parsing lands on the same tenth")
    func roundTrips() {
        for seconds in stride(from: 0.0, through: 4000.0, by: 37.3) {
            let tenth = (seconds * 10).rounded() / 10
            #expect(PreciseTime.parse(PreciseTime.format(seconds)) == tenth)
        }
    }

    @Test("Nudge labels drop a pointless decimal")
    func nudgeLabels() {
        #expect(PreciseTime.nudgeLabel(1) == "1s")
        #expect(PreciseTime.nudgeLabel(0.1) == "0.1s")
    }
}
