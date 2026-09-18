//
//  LastLoadedSong.swift
//  MusicMomentum
//

import Foundation
import MusicKit

/// The song on the practice screen when the app last ran, so it comes back on
/// launch. Kept apart from the saved list: loading a song isn't saving it.
enum LastLoadedSong {
    private static let songIDKey = "lastLoadedSongID"
    private static let catalogIDKey = "lastLoadedCatalogID"

    static var stored: (songID: String, catalogID: String?)? {
        let defaults = UserDefaults.standard
        guard let songID = defaults.string(forKey: songIDKey) else { return nil }
        return (songID, defaults.string(forKey: catalogIDKey))
    }

    static func remember(_ song: Song) {
        let defaults = UserDefaults.standard
        defaults.set(song.id.rawValue, forKey: songIDKey)
        defaults.set(song.catalogID, forKey: catalogIDKey)
    }

    static func forget() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: songIDKey)
        defaults.removeObject(forKey: catalogIDKey)
    }
}
