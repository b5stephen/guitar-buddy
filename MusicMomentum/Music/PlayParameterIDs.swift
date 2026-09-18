//
//  PlayParameterIDs.swift
//  MusicMomentum
//

import Foundation
import MusicKit

/// `PlayParameters` is opaque but `Codable`, and encodes to Apple Music's
/// `playParams` object — the only place MusicKit exposes a library item's
/// catalog ID. Every step is failable so a shape change costs the catalog ID,
/// never a crash.
nonisolated struct PlayParameterIDs: Decodable {
    let id: String
    let catalogId: String?
    let isLibrary: Bool?

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
