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
    /// True once the current queue has actually played. A queue that has been
    /// prepared but never played doesn't keep a `playbackTime` written to it —
    /// it starts at the top whatever you asked for.
    private var hasPlayed = false
    /// A start position asked for before the queue had played, held so it can
    /// be applied again the moment it will stick. This is what makes opening a
    /// saved song at one of its markers land on the marker rather than at 0:00.
    private var pendingStart: TimeInterval?
    /// When the last seek was issued. The player takes a moment to actually
    /// move, and reading it in that window reports the *old* position — which
    /// would yank the bar back to where the user just dragged away from.
    private var lastSeek: ContinuousClock.Instant?

    /// What the loop button is doing, or `nil` when it's off. Only the button
    /// turns looping on and off; the pills reshape it while it runs.
    private(set) var loop: Loop?
    /// Which segment of a clip chain the playhead was last inside, so the
    /// ticker knows which one it has just run past. `nil` means it's outside
    /// the chain — after a jump or a scrub — and the ticker leaves it alone
    /// until it plays back in.
    private var loopIndex: Int?

    /// The loop's scope. Clips are held as copies of the marker's times rather
    /// than the markers themselves, so a deleted marker can't leave a dangling
    /// model object here — `markerDeleted(_:)` prunes it instead.
    enum Loop: Equatable {
        /// Nothing lit: the track repeats end to end.
        case wholeSong
        /// The lit clips, in track order, played back to back.
        case clips([Segment])

        struct Segment: Equatable {
            let markerID: PersistentIdentifier
            let start: TimeInterval
            let end: TimeInterval
        }

        /// The clips in scope — empty for `wholeSong`, so callers can ask
        /// without unwrapping the case every time.
        var segments: [Segment] {
            if case .clips(let segments) = self { return segments }
            return []
        }
    }

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
        // A start the player hasn't taken yet: it would report the top of the
        // track and lose the position the user asked to open at.
        guard pendingStart == nil else { return }
        // Inside the settling window after a seek the player still reports the
        // old position, so leave the value we set optimistically in place.
        if let lastSeek {
            guard lastSeek.duration(to: .now) > .milliseconds(500) else { return }
            self.lastSeek = nil
        }
        let time = player.playbackTime
        // Clamp: the player can report a hair past the end as a track wraps.
        playbackTime = max(0, min(time, duration ?? time))

        advanceChainIfNeeded()
    }

    /// Keeps a clip chain running. Whole-song looping isn't here — that's the
    /// player's own repeat mode, which wraps the track seamlessly instead of
    /// up to a quarter of a second late.
    private func advanceChainIfNeeded() {
        let segments = loop?.segments ?? []
        guard !segments.isEmpty else { return }

        switch Loop.step(segments: segments, time: playbackTime, current: loopIndex) {
        case .inside(let index):
            loopIndex = index
        case .jump(to: let index):
            // Noted before the seek rather than once the playhead lands: a clip
            // can be as short as half a second, which the settling window after
            // a seek can swallow whole, leaving the chain unsure where it is.
            loopIndex = index
            seek(to: segments[index].start)
        case .wait:
            break
        }
    }

    // MARK: - Seeking

    /// Moves the playhead. Safe to call while paused — unlike `playbackRate`,
    /// assigning `playbackTime` doesn't start playback.
    func seek(to time: TimeInterval) {
        let target = max(0, min(time, duration ?? time))
        playbackTime = target
        player.playbackTime = target
        lastSeek = .now
        // Asked for before the queue has played, the player will forget it, so
        // keep it for `play()` to put back.
        guard !hasPlayed else { return }
        pendingStart = target
        // Unless the queue is already running, in which case there's nothing
        // to wait for — and nobody is going to press play to collect it, since
        // the song is playing already.
        if isPlaying {
            Task { await applyPendingStart() }
        }
    }

    /// A seek the user asked for, rather than one the chain made. Forgets
    /// where the playhead was in the chain, so landing past a clip's end isn't
    /// read as "that clip just finished" and bounced straight back.
    private func userSeek(to time: TimeInterval) {
        loopIndex = nil
        seek(to: time)
    }

    /// Nudges the playhead by `offset` seconds, for the skip buttons.
    func skip(by offset: TimeInterval) {
        userSeek(to: playbackTime + offset)
    }

    /// Ends a scrub gesture at `time`: one seek, then the ticker takes over.
    func endScrub(at time: TimeInterval) {
        userSeek(to: time)
        isScrubbing = false
    }

    /// Back to the top of the track — the move you make constantly when
    /// drilling the same passage.
    func restart() {
        userSeek(to: 0)
    }

    /// Asks for Apple Music access if we haven't got it, and reports whether
    /// we have it now. Called when the user reaches for the library — never on
    /// launch, so the system prompt turns up with a reason attached.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        if authorizationStatus != .authorized {
            authorizationStatus = await MusicAuthorization.request()
        }
        return authorizationStatus == .authorized
    }

    /// Whether there's any point offering the library. False only once the
    /// user has said no: an undetermined status still gets a live button,
    /// since tapping it is what brings the prompt up.
    var canUseMusic: Bool {
        authorizationStatus != .denied && authorizationStatus != .restricted
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
        // The loop button is a playback mode and survives a change of song, the
        // way repeat does in any player. Its scope can't: those clips belonged
        // to the last track.
        setLoop(loop == nil ? nil : .wholeSong)
        hasPlayed = false
        pendingStart = nil
        do {
            player.queue = [song]
            // Drilling the same eight bars two hundred times shouldn't shape the
            // user's Apple Music recommendations (iOS 26.4+).
            player.queue.affectsListeningHistory = false
            try await playerBox.prepareToPlay()
            // A fresh queue doesn't carry the old one's repeat mode over.
            applyRepeatMode()
        } catch {
            errorMessage = "Couldn't load that track: \(error.localizedDescription)"
        }
    }

    /// Picks a song from the saved list, which stores only its IDs. Returns
    /// whether the song was found: a saved song can outlive its place in the
    /// library, and the caller needs to know not to send the user to a practice
    /// screen still showing the previous track.
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

    /// Puts a held start position onto the player once it will take one.
    ///
    /// `play()` returning isn't the same as the queue entry being ready: for a
    /// moment after it the player still reports the top of the track and
    /// quietly drops a `playbackTime` written to it, which is what left a song
    /// opened at a marker starting from 0:00. So the write is repeated until
    /// the player reads back somewhere near where it was sent, and given up on
    /// after a second rather than fighting the user's own transport.
    private func applyPendingStart() async {
        guard let target = pendingStart else { return }
        for _ in 0..<10 {
            player.playbackTime = target
            try? await Task.sleep(for: .milliseconds(100))
            // Playing, so it will have moved on a little; anywhere at or past
            // the target means the seek landed.
            if player.playbackTime >= target - 0.5 { break }
        }
        pendingStart = nil
        playbackTime = target
        lastSeek = .now
    }

    // MARK: - Markers

    /// Freezes the moment the user hit the mark button: pauses so the song
    /// doesn't run on while they name the marker, and hands back the playhead
    /// for the editor to open at.
    func pauseForMarking() -> TimeInterval {
        if isPlaying { player.pause() }
        return playbackTime
    }

    /// Drops the playhead at `time` and plays on from there, at the current
    /// practice speed. The marker editor's cue buttons run through this: a
    /// couple of seconds is long enough to tell you a handle landed but not
    /// long enough to tell you how the passage sounds, so nothing stops the
    /// playback but the user.
    func playFrom(_ time: TimeInterval) {
        userSeek(to: time)
        play()
    }

    /// Moves the playhead to a marker's start. Doesn't start or stop playback
    /// — same rule as choosing a song: the user hits play when they're ready.
    ///
    /// It leaves the loop alone in both directions. Only the loop button turns
    /// looping on or off, so jumping out of a running chain is a look around
    /// rather than an escape: the chain picks the playhead up again when it
    /// plays back into one of its clips.
    func jump(to marker: SongMarker) {
        userSeek(to: marker.startTime)
    }

    var isLoopOn: Bool { loop != nil }

    /// Whether this clip is in the running loop's scope.
    func isLooping(_ marker: SongMarker) -> Bool {
        loop?.segments.contains { $0.markerID == marker.persistentModelID } ?? false
    }

    /// The loop button: the only control that starts or stops looping. From
    /// off it loops the whole song, the right default for learning one, and
    /// the pills narrow it from there. From on it stops, whatever the scope —
    /// so however deep a chain gets, one tap ends it.
    func toggleLoop() {
        setLoop(loop == nil ? .wholeSong : nil)
    }

    /// Puts a clip in the loop's scope, or takes it out again. Does nothing
    /// with the button off: a pill tap never starts a loop, it only shapes one
    /// that's already running. Taking the last clip out widens back to the
    /// whole song rather than switching the loop off, since an empty scope is
    /// exactly what the whole song looks like.
    func toggleLoop(for marker: SongMarker) {
        guard let loop, let end = marker.endTime else { return }
        var segments = loop.segments
        if let existing = segments.firstIndex(where: { $0.markerID == marker.persistentModelID }) {
            segments.remove(at: existing)
        } else {
            segments.append(.init(markerID: marker.persistentModelID, start: marker.startTime, end: end))
            // Track order, so a verse and a chorus drill in the order the song
            // plays them without the user having to say so.
            segments.sort { $0.start < $1.start }
        }
        setScope(segments)
    }

    /// Loops one clip and starts it — the long-press shortcut past turning the
    /// button on and then picking the clip out. This is the one place a marker
    /// starts playback, against the rule everywhere else that choosing
    /// something never does; it earns the exception because the user read the
    /// words "Play on Loop" before tapping. It replaces the scope rather than
    /// adding to it: reaching for this means "just this bit, now".
    func playOnLoop(_ marker: SongMarker) {
        guard let end = marker.endTime else { return }
        setLoop(.clips([.init(markerID: marker.persistentModelID, start: marker.startTime, end: end)]))
        seek(to: marker.startTime)
        play()
    }

    /// Keeps the scope in step with a marker the user just edited: new times
    /// if it's still a clip, out of scope if it has become a point.
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

    /// Drops a deleted marker out of the scope, leaving the rest of the chain
    /// looping. Deleting the last clip in scope doesn't switch the loop off —
    /// the button is the only thing that does that — it widens to the whole
    /// song, so an edit can never silently stop a loop the user turned on.
    func markerDeleted(_ marker: SongMarker) {
        guard let loop else { return }
        let segments = loop.segments.filter { $0.markerID != marker.persistentModelID }
        guard segments.count != loop.segments.count else { return }
        setScope(segments)
    }

    /// Narrows the running loop to `segments`, or widens it back to the whole
    /// song when they run out. Arming a clip from outside it moves the
    /// playhead in, so the loop starts now rather than once the rest of the
    /// song has played through.
    private func setScope(_ segments: [Loop.Segment]) {
        setLoop(segments.isEmpty ? .wholeSong : .clips(segments))
        guard !segments.isEmpty,
              !segments.contains(where: { playbackTime >= $0.start && playbackTime < $0.end })
        else { return }
        seek(to: segments[0].start)
    }

    /// The one way the loop changes, so the player's repeat mode can't drift
    /// out of step with it.
    private func setLoop(_ new: Loop?) {
        loop = new
        loopIndex = nil
        applyRepeatMode()
    }

    /// Whole-song looping is the player's own repeat, which wraps the track
    /// seamlessly. A clip chain switches it off — the ticker drives that, and
    /// a track repeating itself underneath would fight it.
    private func applyRepeatMode() {
        player.state.repeatMode = loop == .wholeSong ? .one : MusicPlayer.RepeatMode.none
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
    @discardableResult
    func saveCurrentSong() -> SavedSong? {
        guard let modelContext, let song = selectedSong else { return nil }
        return SavedSong.save(song: song, speed: playbackRate, in: modelContext)
    }
}

extension PlaybackController.Loop {
    /// What a clip chain should do with the playhead at `time`, given the
    /// segment it was last inside. Pure and free of the player, so the
    /// wrap-around rules can be tested directly.
    enum Step: Equatable {
        /// The playhead is in this clip; nothing to do but remember which.
        case inside(Int)
        /// It has run off the end of the clip it was in: go to this one.
        case jump(to: Int)
        /// Outside the chain with no clip to have left — after a jump or a
        /// scrub. Leave the playhead be until it plays back in.
        case wait
    }

    static func step(segments: [Segment], time: TimeInterval, current: Int?) -> Step {
        // Checked first, so clips butted end to end hand over without a seek:
        // the playhead simply walks into the next one and the chain follows.
        if let inside = segments.firstIndex(where: { time >= $0.start && time < $0.end }) {
            return .inside(inside)
        }
        guard let current, current < segments.count, time >= segments[current].end else { return .wait }
        return .jump(to: (current + 1) % segments.count)
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
