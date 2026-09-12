//
//  SongMarker.swift
//  GuitarBuddy
//

import Foundation
import SwiftData

/// A spot in a saved song the user wants to get back to. With only a start
/// time it's a point — "the solo starts here". With an end time as well it's a
/// clip — a passage to drill, and one the player can loop.
///
/// Markers hang off `SavedSong` rather than a song ID so they go when the
/// song is removed from the list, and so the saved list can draw them without
/// a second fetch.
@Model
final class SongMarker {
    var name: String = ""
    /// Seconds into the track.
    var startTime: TimeInterval = 0
    /// Seconds into the track, or `nil` for a point. Always past `startTime`
    /// when set — `set(start:end:)` keeps that true.
    var endTime: TimeInterval?
    var createdAt: Date = Date.now
    var song: SavedSong?

    init(name: String, startTime: TimeInterval, endTime: TimeInterval? = nil, song: SavedSong? = nil) {
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.song = song
    }

    /// Derived from `endTime` rather than stored, so it can't disagree with it.
    var isClip: Bool { endTime != nil }

    /// `1:23` for a point, `1:23 – 1:41` for a clip.
    var timeLabel: String {
        let start = PlaybackScrubber.timeLabel(startTime)
        guard let endTime else { return start }
        return "\(start) – \(PlaybackScrubber.timeLabel(endTime))"
    }
}

// MARK: - Storage

extension SongMarker {
    /// The shortest clip the editor will let you make. Any tighter and the
    /// player can't reliably land inside it between polls.
    static let minimumClipLength: TimeInterval = 0.5

    /// Adds a marker to a saved song. A blank name gets a default that says
    /// what kind of marker it is and where it falls in the list.
    @discardableResult
    static func add(
        to song: SavedSong,
        name: String,
        startTime: TimeInterval,
        endTime: TimeInterval?,
        in context: ModelContext
    ) -> SongMarker {
        let marker = SongMarker(name: "", startTime: 0, song: song)
        context.insert(marker)
        marker.set(name: name, start: startTime, end: endTime)
        try? context.save()
        return marker
    }

    /// Rewrites a marker. The start is clamped at zero, the end is dropped if
    /// it doesn't leave room for a clip, and a blank name gets a default.
    func set(name: String, start: TimeInterval, end: TimeInterval?) {
        startTime = max(0, start)
        if let end, end - startTime >= Self.minimumClipLength {
            endTime = end
        } else {
            endTime = nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed.isEmpty ? defaultName : trimmed
    }

    /// Drops the end time, turning a clip back into a point.
    func clearEnd(in context: ModelContext) {
        endTime = nil
        try? context.save()
    }

    static func delete(_ marker: SongMarker, in context: ModelContext) {
        context.delete(marker)
        try? context.save()
    }

    /// "Clip 3" or "Marker 3", counting the song's other markers of that kind
    /// so the defaults don't collide.
    private var defaultName: String {
        let kind = isClip ? "Clip" : "Marker"
        let siblings = song?.markers.filter { $0 !== self && $0.isClip == isClip }.count ?? 0
        return "\(kind) \(siblings + 1)"
    }
}

extension SavedSong {
    /// Markers in the order they fall in the track.
    var sortedMarkers: [SongMarker] {
        markers.sorted { $0.startTime < $1.startTime }
    }
}
