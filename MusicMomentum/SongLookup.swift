//
//  SongLookup.swift
//  MusicMomentum
//

import MusicKit

/// Turns a stored song ID back into a `Song`.
///
/// The saved list keeps `MusicItemID` raw values, but the player needs the real
/// thing, so tapping a saved song has to look it up again.
enum SongLookup {
    /// The song behind a saved row, or `nil` if neither ID finds it.
    ///
    /// Two IDs because library and catalog IDs are separate namespaces and a
    /// saved song can move between them: removing it from the library orphans
    /// its library ID, and only the catalog ID survives that. Either may be
    /// the one that hits, so both are tried.
    ///
    /// - Parameters:
    ///   - libraryID: The ID the song was saved under.
    ///   - catalogID: Its catalog ID, or `nil` for a song with no catalog
    ///     counterpart — one the user imported themselves, which the library
    ///     is the only place to find.
    static func song(libraryID: String, catalogID: String?) async throws -> Song? {
        if let song = try await libraryItem(id: libraryID) {
            return song
        }
        guard let catalogID else { return nil }
        // Tried as a library ID above when the two match, which is the shape of
        // a song saved straight from Apple Music.
        return try await catalogItem(id: catalogID)
    }

    /// The song with this ID in the user's library. Needs no developer token,
    /// so it works where the catalog is out of reach.
    private static func libraryItem(id: String) async throws -> Song? {
        var request = MusicLibraryRequest<Song>()
        request.filter(matching: \.id, equalTo: MusicItemID(id))
        return try await request.response().items.first
    }

    /// The song with this ID in the Apple Music catalog, or `nil` if the
    /// catalog doesn't have one — which is the answer, not a failure, when the
    /// ID belongs to the other namespace or the track has been pulled.
    private static func catalogItem(id: String) async throws -> Song? {
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
        do {
            return try await request.response().items.first
        } catch let error as MusicDataRequest.Error where error.status == 404 {
            return nil
        }
    }
}
