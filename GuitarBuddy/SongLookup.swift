//
//  SongLookup.swift
//  GuitarBuddy
//

import MusicKit

/// Turns a stored song ID back into a `Song`.
///
/// The saved list keeps `MusicItemID` raw values, but the player needs the real
/// thing, so tapping a saved song has to look it up again.
enum SongLookup {
    /// The song with this ID, or `nil` if it isn't in the library or catalog —
    /// which is what you get when a song has been removed from the library
    /// since it was saved.
    static func song(withID id: String) async throws -> Song? {
        let itemID = MusicItemID(id)

        // Library and catalog IDs are separate namespaces and the picker can
        // hand back either, so a miss in one isn't an answer on its own.
        var libraryRequest = MusicLibraryRequest<Song>()
        libraryRequest.filter(matching: \.id, equalTo: itemID)
        if let song = try await libraryRequest.response().items.first {
            return song
        }

        let catalogRequest = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: itemID)
        return try await catalogRequest.response().items.first
    }
}
