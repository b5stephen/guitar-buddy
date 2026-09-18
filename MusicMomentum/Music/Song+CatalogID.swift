//
//  Song+CatalogID.swift
//  MusicMomentum
//

import Foundation
import MusicKit

nonisolated extension Song {
    /// The Apple Music catalog ID. For a catalog song that's `id`; for a
    /// library song `id` is a library ID (`i.…`) in a separate namespace, and
    /// the catalog ID has to be dug out of `playParameters`. `nil` for a
    /// self-imported track with no catalog counterpart.
    var catalogID: String? {
        playParameters.flatMap(PlayParameterIDs.init)?.catalogID
    }
}
