//
//  SongCatalogIDTests.swift
//  MusicMomentumTests
//

import Foundation
import MusicKit
import Testing
@testable import MusicMomentum

/// `Song` can't be built in a test, but `PlayParameters` is `Codable`, so the
/// part that decides anything can be fed the exact JSON Apple Music sends.
@Suite("Catalog IDs")
struct SongCatalogIDTests {
    private func ids(_ json: String) throws -> PlayParameterIDs {
        try JSONDecoder().decode(PlayParameterIDs.self, from: Data(json.utf8))
    }

    @Test("A catalog song's own ID is its catalog ID")
    func catalogSong() throws {
        let ids = try ids(#"{"id": "1440857781", "kind": "song"}"#)
        #expect(ids.catalogID == "1440857781")
    }

    @Test("A library song reports the catalog original it was matched to")
    func librarySong() throws {
        let ids = try ids(
            #"{"id": "i.gFKW1vJUkkV8ZR", "kind": "song", "isLibrary": true, "catalogId": "1440857781"}"#
        )
        #expect(ids.catalogID == "1440857781")
    }

    /// A self-imported song has no catalog counterpart; handing back its
    /// library ID would store one no catalog lookup can match.
    @Test("A library-only song has no catalog ID")
    func libraryOnlySong() throws {
        let ids = try ids(#"{"id": "i.gFKW1vJUkkV8ZR", "kind": "song", "isLibrary": true}"#)
        #expect(ids.catalogID == nil)
    }

    /// Guards the side door: this only works while MusicKit keeps passing
    /// Apple Music's keys through untouched.
    @Test("The fields survive a round trip through PlayParameters")
    func roundTripsThroughPlayParameters() throws {
        let json = #"{"id": "i.gFKW1vJUkkV8ZR", "kind": "song", "isLibrary": true, "catalogId": "1440857781"}"#
        let parameters = try JSONDecoder().decode(PlayParameters.self, from: Data(json.utf8))
        let ids = try #require(PlayParameterIDs(parameters))
        #expect(ids.catalogID == "1440857781")
    }
}
