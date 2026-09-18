//
//  SongLookup.swift
//  MusicMomentum
//

import MusicKit

/// Turns a stored song ID back into a `Song` for the player.
enum SongLookup {
    /// Tries the library ID first, then the catalog ID: removing a song from
    /// the library orphans its library ID for good, and only the catalog ID
    /// survives that.
    static func song(libraryID: String, catalogID: String?) async throws -> Song? {
        if let song = try await libraryItem(id: libraryID) {
            return song
        }
        guard let catalogID else { return nil }
        return try await catalogItem(id: catalogID)
    }

    /// Needs no developer token, so it works where the catalog is out of reach.
    private static func libraryItem(id: String) async throws -> Song? {
        var request = MusicLibraryRequest<Song>()
        request.filter(matching: \.id, equalTo: MusicItemID(id))
        return try await request.response().items.first
    }

    /// A 404 is the answer, not a failure: the ID belongs to the other
    /// namespace or the track has been pulled.
    private static func catalogItem(id: String) async throws -> Song? {
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
        do {
            return try await request.response().items.first
        } catch let error as MusicDataRequest.Error where error.status == 404 {
            return nil
        }
    }
}
