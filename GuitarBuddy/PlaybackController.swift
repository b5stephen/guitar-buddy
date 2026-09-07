//
//  PlaybackController.swift
//  GuitarBuddy
//

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

    /// True while `loadSavedSpeed(for:)` is writing `playbackRate`, so the
    /// `didSet` doesn't poke the player with a rate mid-load.
    private var isLoadingSavedSpeed = false

    var selectedSong: Song?
    /// Read straight off the player rather than mirrored into a stored
    /// property. `MusicPlayer.State` is `Observable` as of iOS 26.4, so a view
    /// touching this in its body tracks the player directly and stays correct
    /// when playback is started or stopped from outside the app (Control
    /// Centre, headphones, another app taking the queue, or a track ending).
    var isPlaying: Bool { player.state.playbackStatus == .playing }
    var authorizationStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus

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
            guard !isLoadingSavedSpeed else { return }
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
        readPlaybackTime()
        startTicking()
    }

    /// Re-reads the playhead. Only needed where the ticker can't have kept up —
    /// coming back from the background. `isPlaying` needs no such nudge; it
    /// reads the observable player state on demand.
    func refreshPlaybackTime() {
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

    /// Picks a song to practice: queues it at its saved speed and stops there.
    /// Choosing a track is not the same as wanting it to start — the user hits
    /// play when they've got the guitar in their hands.
    func select(song: Song) async {
        selectedSong = song
        loadSavedSpeed(for: song)
        errorMessage = nil
        rateWarning = nil
        playbackTime = 0
        do {
            player.queue = [song]
            // Drilling the same eight bars two hundred times shouldn't shape the
            // user's Apple Music recommendations (iOS 26.4+).
            player.queue.affectsListeningHistory = false
            try await playerBox.prepareToPlay()
        } catch {
            errorMessage = "Couldn't load that track: \(error.localizedDescription)"
        }
    }

    /// Picks a song from the saved list, which stores only its ID. Returns
    /// whether the song was found: a saved song can outlive its place in the
    /// library, and the caller needs to know not to send the user to a practice
    /// screen still showing the previous track.
    @discardableResult
    func select(savedID: String) async -> Bool {
        do {
            guard let song = try await SongLookup.song(withID: savedID) else {
                errorMessage = "That song isn't in your library or on Apple Music any more."
                return false
            }
            await select(song: song)
            return true
        } catch {
            errorMessage = "Couldn't find that song: \(error.localizedDescription)"
            return false
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            Task {
                do {
                    try await playerBox.play()
                    try? await Task.sleep(for: .milliseconds(300))
                    applyRateIfPossible()
                    verifyRateStuck()
                } catch {
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

    /// Loads the saved speed for this song, if it's on the saved list, falling
    /// back to 100%.
    private func loadSavedSpeed(for song: Song) {
        isLoadingSavedSpeed = true
        defer { isLoadingSavedSpeed = false }

        guard let modelContext else {
            playbackRate = 1.0
            return
        }
        playbackRate = SavedSong.find(songID: song.id.rawValue, in: modelContext)?.speed ?? 1.0
    }

    /// Adds the current song to the saved list at the current speed, or updates
    /// it if it's already there. Deliberately *not* called from `playbackRate`'s
    /// `didSet` — speeds are only persisted when the user explicitly saves a
    /// song, so the list stays curated rather than a log of everything ever
    /// played.
    func saveCurrentSong() {
        guard let modelContext, let song = selectedSong else { return }
        SavedSong.save(song: song, speed: playbackRate, in: modelContext)
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

    nonisolated func prepareToPlay() async throws {
        try await player.prepareToPlay()
    }
}
