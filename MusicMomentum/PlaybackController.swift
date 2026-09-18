//
//  PlaybackController.swift
//  MusicMomentum
//

import Foundation
import MusicKit
import Observation
import SwiftData

/// Wraps `ApplicationMusicPlayer`; the only thing in the app that talks to it.
@MainActor
@Observable
final class PlaybackController {
    static let speedRange: ClosedRange<Double> = 0.3...1.0

    private let player = ApplicationMusicPlayer.shared
    private let playerBox = MusicPlayerBox(player: ApplicationMusicPlayer.shared)
    private var modelContext: ModelContext?

    /// Stops `playbackRate`'s `didSet` poking the player mid-load.
    private var isLoadingSavedSpeed = false

    var selectedSong: Song?
    /// Read off the player, not mirrored: `MusicPlayer.State` is `Observable`
    /// (iOS 26.4), so this stays right when playback is started or stopped
    /// from outside the app.
    var isPlaying: Bool { player.state.playbackStatus == .playing }
    var authorizationStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus

    /// MusicKit publishes no change signal for the playhead, so it's polled.
    private var tickObservation: Task<Void, Never>?

    private(set) var playbackTime: TimeInterval = 0
    var duration: TimeInterval? { selectedSong?.duration }
    /// Suspends the ticker so the thumb doesn't fight the playhead.
    var isScrubbing = false
    /// A queue that has been prepared but never played drops any
    /// `playbackTime` written to it and starts at the top.
    private var hasPlayed = false
    /// A seek asked for before `hasPlayed`, re-applied once it will stick.
    private var pendingStart: TimeInterval?
    /// For a moment after a seek the player still reports the *old* position,
    /// which would yank the bar back to where the user just dragged from.
    private var lastSeek: ContinuousClock.Instant?

    /// `nil` when the loop button is off. Only the button turns looping on and
    /// off; the pills reshape the scope while it runs.
    private(set) var loop: Loop?
    /// Which segment of a clip chain the playhead was last inside. `nil` after
    /// a jump or scrub: the ticker waits until it plays back into the chain.
    private var loopIndex: Int?

    /// Segments are copies of marker times, not the markers, so a deleted
    /// marker can't leave a dangling model object here.
    enum Loop: Equatable {
        case wholeSong
        /// In track order, played back to back.
        case clips([Segment])

        struct Segment: Equatable {
            let markerID: PersistentIdentifier
            let start: TimeInterval
            let end: TimeInterval
        }

        var segments: [Segment] {
            if case .clips(let segments) = self { return segments }
            return []
        }
    }

    var playbackRate: Double = 1.0 {
        didSet {
            guard !isLoadingSavedSpeed else { return }
            // Assigning `playbackRate` on a paused player starts it.
            if isPlaying {
                applyRateIfPossible()
            }
        }
    }

    var errorMessage: String?
    /// Set when the player silently refuses the requested rate.
    var rateWarning: String?

    // MARK: - Setup

    /// Kept out of `init` so the class stays easy to preview.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        readPlaybackTime()
        startTicking()
    }

    /// For coming back from the background, where the ticker couldn't keep up.
    func refreshPlaybackTime() {
        readPlaybackTime()
    }

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
        guard pendingStart == nil else { return }
        if let lastSeek {
            guard lastSeek.duration(to: .now) > .milliseconds(500) else { return }
            self.lastSeek = nil
        }
        let time = player.playbackTime
        // The player can report a hair past the end as a track wraps.
        playbackTime = max(0, min(time, duration ?? time))

        advanceChainIfNeeded()
    }

    /// Whole-song looping isn't here: that's the player's own repeat mode,
    /// which wraps seamlessly instead of up to a poll late.
    private func advanceChainIfNeeded() {
        let segments = loop?.segments ?? []
        guard !segments.isEmpty else { return }

        switch Loop.step(segments: segments, time: playbackTime, current: loopIndex) {
        case .inside(let index):
            loopIndex = index
        case .jump(to: let index):
            // Set before the seek: a half-second clip can be swallowed whole by
            // the settling window, leaving the chain unsure where it is.
            loopIndex = index
            seek(to: segments[index].start)
        case .wait:
            break
        }
    }

    // MARK: - Seeking

    /// Unlike `playbackRate`, assigning `playbackTime` doesn't start playback.
    func seek(to time: TimeInterval) {
        let target = max(0, min(time, duration ?? time))
        playbackTime = target
        player.playbackTime = target
        lastSeek = .now
        guard !hasPlayed else { return }
        pendingStart = target
        if isPlaying {
            Task { await applyPendingStart() }
        }
    }

    /// Forgets where the playhead was in the chain, so landing past a clip's
    /// end isn't read as "that clip just finished" and bounced back.
    private func userSeek(to time: TimeInterval) {
        loopIndex = nil
        seek(to: time)
    }

    func skip(by offset: TimeInterval) {
        userSeek(to: playbackTime + offset)
    }

    func endScrub(at time: TimeInterval) {
        userSeek(to: time)
        isScrubbing = false
    }

    func restart() {
        userSeek(to: 0)
    }

    /// Called when the user reaches for the library, never on launch, so the
    /// system prompt turns up with a reason attached.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        if authorizationStatus != .authorized {
            authorizationStatus = await MusicAuthorization.request()
        }
        return authorizationStatus == .authorized
    }

    /// Undetermined still counts: tapping the button is what brings the prompt up.
    var canUseMusic: Bool {
        authorizationStatus != .denied && authorizationStatus != .restricted
    }

    // MARK: - Playback

    /// Queues the song at its saved speed without starting it — the user hits
    /// play once the guitar is in their hands.
    func select(song: Song) async {
        selectedSong = song
        loadSavedSpeed(for: song)
        errorMessage = nil
        rateWarning = nil
        playbackTime = 0
        // The loop button survives a change of song, like repeat in any
        // player; its scope can't, since those clips belonged to the last track.
        setLoop(loop == nil ? nil : .wholeSong)
        hasPlayed = false
        pendingStart = nil
        do {
            player.queue = [song]
            // Drilling eight bars two hundred times shouldn't shape
            // recommendations (iOS 26.4+).
            player.queue.affectsListeningHistory = false
            try await playerBox.prepareToPlay()
            // A fresh queue doesn't carry the old one's repeat mode over.
            applyRepeatMode()
        } catch {
            errorMessage = "Couldn't load that track: \(error.localizedDescription)"
        }
    }

    /// Returns whether the song was found, so the caller doesn't send the user
    /// to a practice screen still showing the previous track.
    @discardableResult
    func select(saved: SavedSong) async -> Bool {
        do {
            guard let song = try await SongLookup.song(
                libraryID: saved.songID,
                catalogID: saved.catalogID
            ) else {
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
            play()
        }
    }

    private func play() {
        Task {
            do {
                try await playerBox.play()
                hasPlayed = true
                await applyPendingStart()
                try? await Task.sleep(for: .milliseconds(300))
                applyRateIfPossible()
                verifyRateStuck()
            } catch {
                errorMessage = "Couldn't resume: \(error.localizedDescription)"
            }
        }
    }

    /// `play()` returning isn't the same as the queue entry being ready: for a
    /// moment after it the player still drops a `playbackTime` written to it.
    /// So the write is repeated until the player reads back near the target,
    /// and given up on after a second rather than fighting the user's transport.
    private func applyPendingStart() async {
        guard let target = pendingStart else { return }
        for _ in 0..<10 {
            player.playbackTime = target
            try? await Task.sleep(for: .milliseconds(100))
            if player.playbackTime >= target - 0.5 { break }
        }
        pendingStart = nil
        playbackTime = target
        lastSeek = .now
    }

    // MARK: - Markers

    /// Pauses so the song doesn't run on while the user names the marker, and
    /// returns the playhead for the editor to open at.
    func pauseForMarking() -> TimeInterval {
        if isPlaying { player.pause() }
        return playbackTime
    }

    func playFrom(_ time: TimeInterval) {
        userSeek(to: time)
        play()
    }

    /// Doesn't start or stop playback, and leaves the loop alone: jumping out
    /// of a running chain is a look around, and the chain picks the playhead
    /// up again when it plays back into a clip.
    func jump(to marker: SongMarker) {
        userSeek(to: marker.startTime)
    }

    var isLoopOn: Bool { loop != nil }

    func isLooping(_ marker: SongMarker) -> Bool {
        loop?.segments.contains { $0.markerID == marker.persistentModelID } ?? false
    }

    /// The only control that starts or stops looping. From off it loops the
    /// whole song; from on it stops whatever the scope, so one tap ends any chain.
    func toggleLoop() {
        setLoop(loop == nil ? .wholeSong : nil)
    }

    /// Does nothing with the button off: a pill tap never starts a loop.
    /// Taking the last clip out widens to the whole song rather than stopping.
    func toggleLoop(for marker: SongMarker) {
        guard let loop, let end = marker.endTime else { return }
        var segments = loop.segments
        if let existing = segments.firstIndex(where: { $0.markerID == marker.persistentModelID }) {
            segments.remove(at: existing)
        } else {
            segments.append(.init(markerID: marker.persistentModelID, start: marker.startTime, end: end))
            segments.sort { $0.start < $1.start }
        }
        setScope(segments)
    }

    /// The one place a marker starts playback, against the rule everywhere
    /// else that choosing something never does: the user read the words
    /// "Play on Loop" before tapping. Replaces the scope rather than adding to it.
    func playOnLoop(_ marker: SongMarker) {
        guard let end = marker.endTime else { return }
        setLoop(.clips([.init(markerID: marker.persistentModelID, start: marker.startTime, end: end)]))
        seek(to: marker.startTime)
        play()
    }

    func markerChanged(_ marker: SongMarker) {
        guard let loop else { return }
        var segments = loop.segments
        guard let index = segments.firstIndex(where: { $0.markerID == marker.persistentModelID }) else { return }
        if let end = marker.endTime {
            segments[index] = .init(markerID: marker.persistentModelID, start: marker.startTime, end: end)
            segments.sort { $0.start < $1.start }
        } else {
            segments.remove(at: index)
        }
        setScope(segments)
    }

    /// Deleting the last clip in scope widens to the whole song rather than
    /// switching off, so an edit can never silently stop a loop the user turned on.
    func markerDeleted(_ marker: SongMarker) {
        guard let loop else { return }
        let segments = loop.segments.filter { $0.markerID != marker.persistentModelID }
        guard segments.count != loop.segments.count else { return }
        setScope(segments)
    }

    /// Arming a clip from outside it moves the playhead in, so the loop starts
    /// now rather than once the rest of the song has played through.
    private func setScope(_ segments: [Loop.Segment]) {
        setLoop(segments.isEmpty ? .wholeSong : .clips(segments))
        guard !segments.isEmpty,
              !segments.contains(where: { playbackTime >= $0.start && playbackTime < $0.end })
        else { return }
        seek(to: segments[0].start)
    }

    /// The one way the loop changes, so the player's repeat mode can't drift.
    private func setLoop(_ new: Loop?) {
        loop = new
        loopIndex = nil
        applyRepeatMode()
    }

    /// A clip chain needs repeat off: the ticker drives it, and a track
    /// repeating underneath would fight it.
    private func applyRepeatMode() {
        player.state.repeatMode = loop == .wholeSong ? .one : MusicPlayer.RepeatMode.none
    }

    private func applyRateIfPossible() {
        player.state.playbackRate = Float(playbackRate)
    }

    /// Apple has toggled third-party rate control for DRM content on and off
    /// across releases, so surface a silent reset rather than pretending the
    /// slowdown worked.
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

    private func loadSavedSpeed(for song: Song) {
        isLoadingSavedSpeed = true
        defer { isLoadingSavedSpeed = false }

        guard let modelContext else {
            playbackRate = 1.0
            return
        }
        playbackRate = SavedSong.find(songID: song.id.rawValue, in: modelContext)?.speed ?? 1.0
    }

    /// Deliberately not called from `playbackRate`'s `didSet`: speeds persist
    /// only on an explicit save, so the list stays curated.
    @discardableResult
    func saveCurrentSong() -> SavedSong? {
        guard let modelContext, let song = selectedSong else { return nil }
        return SavedSong.save(song: song, speed: playbackRate, in: modelContext)
    }
}

extension PlaybackController.Loop {
    /// Pure and free of the player, so the wrap-around rules can be tested.
    enum Step: Equatable {
        case inside(Int)
        case jump(to: Int)
        /// Outside the chain with no clip to have left; leave the playhead be.
        case wait
    }

    static func step(segments: [Segment], time: TimeInterval, current: Int?) -> Step {
        // Checked first, so clips butted end to end hand over without a seek.
        if let inside = segments.firstIndex(where: { time >= $0.start && time < $0.end }) {
            return .inside(inside)
        }
        guard let current, current < segments.count, time >= segments[current].end else { return .wait }
        return .jump(to: (current + 1) % segments.count)
    }
}

/// `ApplicationMusicPlayer` isn't `Sendable`, and `play()` is `nonisolated
/// async`, so awaiting it from a `@MainActor` type would send the player
/// across an isolation boundary. `.shared` is a process-wide singleton only
/// ever touched from the main actor, so routing the call through this box is safe.
nonisolated private struct MusicPlayerBox: @unchecked Sendable {
    let player: ApplicationMusicPlayer

    nonisolated func play() async throws {
        try await player.play()
    }

    nonisolated func prepareToPlay() async throws {
        try await player.prepareToPlay()
    }
}
