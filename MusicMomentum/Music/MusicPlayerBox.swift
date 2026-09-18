//
//  MusicPlayerBox.swift
//  MusicMomentum
//

import MusicKit

/// `ApplicationMusicPlayer` isn't `Sendable`, and `play()` is `nonisolated
/// async`, so awaiting it from a `@MainActor` type would send the player
/// across an isolation boundary. `.shared` is a process-wide singleton only
/// ever touched from the main actor, so routing the call through this box is safe.
nonisolated struct MusicPlayerBox: @unchecked Sendable {
    let player: ApplicationMusicPlayer

    nonisolated func play() async throws {
        try await player.play()
    }

    nonisolated func prepareToPlay() async throws {
        try await player.prepareToPlay()
    }
}
