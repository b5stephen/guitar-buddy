//
//  SongMarker.swift
//  MusicMomentum
//

import Foundation
import SwiftData

/// A point (start only) or a clip (start and end) in a saved song.
@Model
final class SongMarker {
    var name: String = ""
    var startTime: TimeInterval = 0
    /// `nil` for a point. Always past `startTime` when set — `set(name:start:end:)` keeps that true.
    var endTime: TimeInterval?
    var createdAt: Date = Date.now
    var song: SavedSong?

    init(name: String, startTime: TimeInterval, endTime: TimeInterval? = nil, song: SavedSong? = nil) {
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.song = song
    }

    var isClip: Bool { endTime != nil }

    var timeLabel: String {
        let start = PlaybackScrubber.timeLabel(startTime)
        guard let endTime else { return start }
        return "\(start) – \(PlaybackScrubber.timeLabel(endTime))"
    }
}

// MARK: - Storage

extension SongMarker {
    /// Any tighter and the player can't reliably land inside the clip between ticker polls.
    static let minimumClipLength: TimeInterval = 0.5

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

    /// Clamps the start at zero, drops an end that doesn't leave room for a clip,
    /// and gives a blank name a default.
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

    func clearEnd(in context: ModelContext) {
        endTime = nil
        try? context.save()
    }

    static func delete(_ marker: SongMarker, in context: ModelContext) {
        context.delete(marker)
        try? context.save()
    }

    private var defaultName: String {
        let kind = isClip ? "Clip" : "Marker"
        let siblings = song?.markers.filter { $0 !== self && $0.isClip == isClip }.count ?? 0
        return "\(kind) \(siblings + 1)"
    }
}

extension SavedSong {
    var sortedMarkers: [SongMarker] {
        markers.sorted { $0.startTime < $1.startTime }
    }
}
