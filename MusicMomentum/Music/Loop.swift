//
//  Loop.swift
//  MusicMomentum
//

import Foundation
import SwiftData

/// Segments are copies of marker times, not the markers, so a deleted
/// marker can't leave a dangling model object here.
enum Loop: Equatable {
    case wholeSong
    /// In track order, played back to back.
    case clips([Segment])

    struct Segment: Equatable {
        let markerID: PersistentIdentifier
        let start: TimeInterval
        let end: TimeInterval
    }

    var segments: [Segment] {
        if case .clips(let segments) = self { return segments }
        return []
    }
}

extension Loop {
    /// Pure and free of the player, so the wrap-around rules can be tested.
    enum Step: Equatable {
        case inside(Int)
        case jump(to: Int)
        /// Outside the chain with no clip to have left; leave the playhead be.
        case wait
    }

    static func step(segments: [Segment], time: TimeInterval, current: Int?) -> Step {
        // Checked first, so clips butted end to end hand over without a seek.
        if let inside = segments.firstIndex(where: { time >= $0.start && time < $0.end }) {
            return .inside(inside)
        }
        guard let current, current < segments.count, time >= segments[current].end else { return .wait }
        return .jump(to: (current + 1) % segments.count)
    }
}
