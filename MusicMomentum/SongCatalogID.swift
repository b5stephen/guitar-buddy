//
//  SongCatalogID.swift
//  MusicMomentum
//

import Foundation
import MusicKit

nonisolated extension Song {
    /// This song's Apple Music catalog ID, which is what `id` already holds for
    /// a song picked out of the catalog but *not* for one picked out of the
    /// library — there `id` is a library ID (`i.…`), a separate namespace the
    /// catalog knows nothing about.
    ///
    /// Saving it alongside the library ID is what lets a song still be found
    /// after the user removes it from their library, which orphans the library
    /// ID for good.
    ///
    /// `nil` for a song that has no catalog counterpart at all — a track the
    /// user imported themselves, which no lookup will ever bring back.
    var catalogID: String? {
        playParameters.flatMap(PlayParameterIDs.init)?.catalogID
    }
}

/// The IDs inside a `PlayParameters`.
///
/// MusicKit exposes `PlayParameters` as an opaque value with no readable
/// fields, but it is `Codable`, and what it encodes to is Apple Music's own
/// `playParams` object — the only place the framework puts a library item's
/// catalog ID. Decoding it back out is a side door, so every step of it is
/// failable: a shape change costs us the catalog ID, never a crash.
nonisolated struct PlayParameterIDs: Decodable {
    /// The ID for whichever namespace this song came from.
    let id: String
    /// Present only on a library item, pointing at its catalog original.
    let catalogId: String?
    /// Whether `id` is a library ID.
    let isLibrary: Bool?

    /// The catalog ID however this song reached us: the explicit one on a
    /// library item, or `id` itself on a catalog item.
    var catalogID: String? {
        if let catalogId { return catalogId }
        return isLibrary == true ? nil : id
    }

    init?(_ parameters: PlayParameters) {
        guard let data = try? JSONEncoder().encode(parameters),
              let decoded = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = decoded
    }
}
