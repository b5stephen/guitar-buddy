//
//  SongSpeedPreference.swift
//  GuitarBuddy
//

import Foundation
import SwiftData

/// One row per song, remembering the last speed the user practiced it at.
///
/// `songID` stores MusicKit's `MusicItemID` raw value (a `String`) rather than
/// the `Song` struct itself, since `Song` isn't a SwiftData-storable type.
@Model
final class SongSpeedPreference {
    #Unique<SongSpeedPreference>([\.songID])

    var songID: String = ""
    var speed: Double = 1.0
    var title: String = ""
    var artistName: String = ""
    var lastUsed: Date = Date.now

    init(
        songID: String,
        speed: Double,
        title: String = "",
        artistName: String = "",
        lastUsed: Date = .now
    ) {
        self.songID = songID
        self.speed = speed
        self.title = title
        self.artistName = artistName
        self.lastUsed = lastUsed
    }
}
