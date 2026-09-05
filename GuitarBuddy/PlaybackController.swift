//
//  PlaybackController.swift
//  GuitarBuddy
//

import Combine
import Foundation
import MusicKit
import Observation
import SwiftData

/// Wraps `ApplicationMusicPlayer` and exposes state SwiftUI observes directly
/// via the Observation framework — no `ObservableObject`, no Combine.
@MainActor
@Observable
final class PlaybackController {
    /// Slowest and fastest practice speeds the app offers.
    static let speedRange: ClosedRange<Double> = 0.3...1.0

    private let player = ApplicationMusicPlayer.shared
    private let playerBox = MusicPlayerBox(player: ApplicationMusicPlayer.shared)
    private var modelContext: ModelContext?

    /// True while `loadPreference(for:)` is writing `playbackRate`, so the
    /// `didSet` doesn't poke the player with a rate mid-load.
    private var isLoadingPreference = false

    var selectedSong: Song?
    /// Mirrors `player.state.playbackStatus`, so the UI stays correct when
    /// playback is started or stopped from outside the app (Control Centre,
    /// headphones, another app taking the queue, or a track simply ending).
    private(set) var isPlaying = false
    var authorizationStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus

    /// Watches the shared player so `isPlaying` never drifts from reality.
    private var stateObservation: Task<Void, Never>?
    /// Drives `playbackTime`. MusicKit publishes no change signal for the
    /// playhead, so the only way to follow it is to keep asking.
    private var tickObservation: Task<Void, Never>?

    /// Seconds into the current track. Written by the ticker while playing and
    /// by `seek(to:)` when the user scrubs.
    private(set) var playbackTime: TimeInterval = 0
    /// Length of the current track, or `nil` when Apple Music didn't give one.
    var duration: TimeInterval? { selectedSong?.duration }
    /// True while the user has a finger on the scrubber, which suspends the
    /// ticker so the thumb doesn't fight the playhead.
    var isScrubbing = false
    /// When the last seek was issued. The player takes a moment to actually
    /// move, and reading it in that window reports the *old* position — which
    /// would yank the bar back to where the user just dragged away from.
    private var lastSeek: ContinuousClock.Instant?

    var playbackRate: Double = 1.0 {
        didSet {
            guard !isLoadingPreference else { return }
            // Only push the rate while playing: assigning `playbackRate` on a
            // paused player makes it start, so a paused song would jump to life
            // just because the user turned the speed dial.
            if isPlaying {
                applyRateIfPossible()
            }
        }
    }

    var errorMessage: String?
    /// Set when the player silently refuses the requested rate — see the
    /// caveat about Apple toggling third-party rate control for DRM content.
    var rateWarning: String?

    // MARK: - Setup

    /// Call once from the view's `.task`, passing the environment's context —
    /// kept out of `init` so this class stays easy to preview.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        startObservingPlayerState()
    }

    /// `MusicPlayerState` is an `ObservableObject`; its `objectWillChange` is
    /// the only signal MusicKit gives for externally-driven transport changes.
    private func startObservingPlayerState() {
        guard stateObservation == nil else { return }
        syncPlaybackState()
        startTicking()
        let state = player.state
        stateObservation = Task { [weak self] in
            for await _ in state.objectWillChange.values {
                // "willChange" — let the new value land before reading it.
                try? await Task.sleep(for: .milliseconds(30))
                guard let self else { return }
                self.syncPlaybackState()
            }
        }
    }

    /// Pulls the truth back out of the player.
    func syncPlaybackState() {
        isPlaying = player.state.playbackStatus == .playing
        readPlaybackTime()
    }

    /// Polls the playhead a few times a second — often enough for the elapsed
    /// time to look live, cheap enough to leave running.
    private func startTicking() {
        guard tickObservation == nil else { return }
        tickObservation = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                guard self.isPlaying, !self.isScrubbing else { continue }
                self.readPlaybackTime()
            }
        }
    }

    private func readPlaybackTime() {
        // Inside the settling window after a seek the player still reports the
        // old position, so leave the value we set optimistically in place.
        if let lastSeek {
            guard lastSeek.duration(to: .now) > .milliseconds(500) else { return }
            self.lastSeek = nil
        }
        let time = player.playbackTime
        // Clamp: the player can report a hair past the end as a track wraps.
        playbackTime = max(0, min(time, duration ?? time))
    }

    // MARK: - Seeking

    /// Moves the playhead. Safe to call while paused — unlike `playbackRate`,
    /// assigning `playbackTime` doesn't start playback.
    func seek(to time: TimeInterval) {
        let target = max(0, min(time, duration ?? time))
        playbackTime = target
        player.playbackTime = target
        lastSeek = .now
    }

    /// Nudges the playhead by `offset` seconds, for the skip buttons.
    func skip(by offset: TimeInterval) {
        seek(to: playbackTime + offset)
    }

    /// Ends a scrub gesture at `time`: one seek, then the ticker takes over.
    func endScrub(at time: TimeInterval) {
        seek(to: time)
        isScrubbing = false
    }

    /// Back to the top of the track — the move you make constantly when
    /// drilling the same passage.
    func restart() {
        seek(to: 0)
    }

    func requestAuthorizationIfNeeded() async {
        guard authorizationStatus != .authorized else { return }
        authorizationStatus = await MusicAuthorization.request()
    }

    // MARK: - Playback

    func play(song: Song) async {
        loadPreference(for: song)
        errorMessage = nil
        rateWarning = nil
        playbackTime = 0
        do {
            player.queue = [song]
            try await playerBox.play()
            syncPlaybackState()
            // The player resets rate to 1.0 on play(), so re-apply shortly after.
            try? await Task.sleep(for: .milliseconds(300))
            applyRateIfPossible()
            verifyRateStuck()
        } catch {
            syncPlaybackState()
            errorMessage = "Couldn't play that track: \(error.localizedDescription)"
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            syncPlaybackState()
        } else {
            Task {
                do {
                    try await playerBox.play()
                    syncPlaybackState()
                    try? await Task.sleep(for: .milliseconds(300))
                    applyRateIfPossible()
                    verifyRateStuck()
                } catch {
                    syncPlaybackState()
                    errorMessage = "Couldn't resume: \(error.localizedDescription)"
                }
            }
        }
    }

    private func applyRateIfPossible() {
        player.state.playbackRate = Float(playbackRate)
    }

    /// Best-effort check that the requested rate actually took. Apple has
    /// toggled third-party playback-rate control for Apple Music (DRM)
    /// content on and off across releases, so surface a silent reset rather
    /// than pretending the slowdown worked.
    private func verifyRateStuck() {
        guard isPlaying else { return }
        let actual = Double(player.state.playbackRate)
        if abs(actual - playbackRate) > 0.01 {
            rateWarning = "This track is playing at \(Int(actual * 100))% — Apple Music didn't accept the slower speed."
        } else {
            rateWarning = nil
        }
    }

    // MARK: - Persistence

    /// Loads a saved speed for this song, if one exists, falling back to 100%.
    private func loadPreference(for song: Song) {
        isLoadingPreference = true
        defer { isLoadingPreference = false }

        guard let modelContext else {
            playbackRate = 1.0
            return
        }
        let songID = song.id.rawValue
        let descriptor = FetchDescriptor<SongSpeedPreference>(
            predicate: #Predicate { $0.songID == songID }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            playbackRate = existing.speed
        } else {
            playbackRate = 1.0
        }
    }

    /// Upserts the current speed for the current song. Deliberately *not*
    /// called from `playbackRate`'s `didSet` — speeds are only persisted when
    /// the user explicitly saves a song, so the store stays a curated list
    /// rather than a log of everything ever played.
    func saveCurrentSpeed() {
        guard let modelContext, let song = selectedSong else { return }
        let songID = song.id.rawValue
        let descriptor = FetchDescriptor<SongSpeedPreference>(
            predicate: #Predicate { $0.songID == songID }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.speed = playbackRate
            existing.lastUsed = .now
        } else {
            modelContext.insert(
                SongSpeedPreference(
                    songID: songID,
                    speed: playbackRate,
                    title: song.title,
                    artistName: song.artistName
                )
            )
        }
        try? modelContext.save()
    }
}

/// `ApplicationMusicPlayer` isn't `Sendable`, but `.shared` is a process-wide
/// singleton and everything else here touches it only from the main actor.
/// `play()` is `nonisolated async`, so awaiting it directly from a `@MainActor`
/// type would mean sending the player across an isolation boundary; routing the
/// call through this box keeps that hop inside a nonisolated context instead.
nonisolated private struct MusicPlayerBox: @unchecked Sendable {
    let player: ApplicationMusicPlayer

    nonisolated func play() async throws {
        try await player.play()
    }
}
