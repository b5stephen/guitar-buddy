# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Music Momentum is an iOS guitar-practice app: pick a song from Apple Music, slow it down (30–100%), mark points and clips in it, and loop clips back to back. SwiftUI + SwiftData + MusicKit, Swift 6 with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency, deployment target iOS 26.4. One scheme, `MusicMomentum`.

## Commands

There is no Package.swift or Makefile; everything goes through `xcodebuild`. The destination must be a simulator on iOS ≥ 26.4 (the deployment target) — older runtimes are rejected with a "doesn't match deployment target" error, so check `xcrun simctl list devices available` if the one below is gone.

```sh
# Build
xcodebuild build -scheme MusicMomentum -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'

# Unit tests (Swift Testing, in MusicMomentumTests)
xcodebuild test -scheme MusicMomentum -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MusicMomentumTests

# One suite / one test
xcodebuild test -scheme MusicMomentum -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:MusicMomentumTests/LoopChainTests
xcodebuild test -scheme MusicMomentum -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:MusicMomentumTests/SavedSongTests/reSaveUpdatesInPlace
```

Anything that touches Apple Music (playback, `SongLookup`, the pickers) needs a real device with a subscription and the MusicKit entitlement — the simulator can build and run the unit tests but can't play. Unit tests are written so they never need MusicKit; keep it that way.

## Architecture

**Two tabs, one player.** `RootTabView` owns the single `PlaybackController` and passes it to both `PracticeView` (Practice tab) and `SavedSongsView` (Saved tab). Tapping a saved song hands it to the controller and switches to the practice tab; the practice tab is never torn down, so playback state survives tab switches.

**`PlaybackController`** (`@MainActor @Observable`) wraps `ApplicationMusicPlayer.shared` and is the only thing that talks to the player. Things to know before touching it:
- MusicKit gives no playhead change signal, so a ticker `Task` polls `playbackTime`. After a `seek` there's a settling window during which the player still reports the old position; the ticker ignores the player then and trusts the optimistic value. Likewise a `pendingStart` is held until the queue has actually played, because a queue that's prepared but unplayed drops writes to `playbackTime`.
- Setting `playbackRate` on a paused player starts it, so the rate is only pushed while playing. Apple has toggled third-party rate control for DRM tracks across releases; `rateWarning` surfaces a silent reset.
- Looping is `Loop?`: `.wholeSong` uses the player's own repeat mode; `.clips([Segment])` switches repeat off and the ticker drives jumps via the pure `Loop.step(segments:time:current:)`. Segments are *copies* of marker times keyed by `PersistentIdentifier`, not the `SongMarker` objects — `markerChanged(_:)`/`markerDeleted(_:)` keep them in sync. The loop button is the only thing that turns looping on/off; pills only reshape scope, and running out of clips widens to whole-song rather than stopping.
- Rule the UI follows: choosing something (a song, a marker) never starts playback. The one exception is the "Play on Loop" long-press action, and the comment there explains why.
- Speeds are persisted only on explicit save, never from `playbackRate`'s `didSet`.

**Persistence** is two SwiftData models, listed in `AppSchema.models` — add new models there and the app, previews and tests all pick them up. `AppSchema.inMemoryContainer()` is what tests and previews use.
- `SavedSong` stores `songID` (may be a library `i.…` ID) *and* `catalogID` separately, because library IDs stop resolving the moment the user removes the song from their library. `SongLookup` tries both. `catalogID` comes from `Song.catalogID` in `Song+CatalogID.swift`, whose `PlayParameterIDs` round-trips MusicKit's opaque `PlayParameters` through JSON to read the `catalogId` field — a deliberate side door where every step is failable.
- Artwork is stored as the JSON-encoded MusicKit `Artwork`, not a URL, so rows draw with `ArtworkImage` (see the comment in `SavedSong.swift` for why not `AsyncImage`).
- `SongMarker` is a point (`endTime == nil`) or a clip; `isClip` is derived, never stored. All mutation goes through `SongMarker.add/set/clearEnd/delete` and `SavedSong.save/touch`, which enforce the invariants (start ≥ 0, clip ≥ `minimumClipLength`, default names) and call `context.save()`.

**Storage APIs take plain values, not MusicKit types** (`SavedSong.save(songID:catalogID:title:…)` with a `Song` overload on top), because `Song`/`Artwork` have no public initialisers and tests can't construct them. Follow that split when adding storage logic so it stays testable.

**Tests** (`MusicMomentumTests/`, Swift Testing, `@MainActor @Suite`) cover the storage rules and the loop-chain stepping logic — the parts where a bug silently corrupts user data. Each test builds its own in-memory `ModelContext` in `init()`.

## Layout

Folders are Xcode synchronized groups, so moving a file on disk is the whole job. `App/` is the entry point and tab shell, `Model/` the SwiftData models, `Music/` everything that talks to MusicKit outside the UI (`PlaybackController`, `Loop`, `SongLookup`), and one folder per screen (`Practice/`, `Saved/`), with a flow that's only reached from one screen nested inside it (`Practice/SongPicker/`). Promote a nested flow when a second screen presents it; there is no `Components/` folder until a view is actually shared. Tests mirror `Model/` and `Music/`.

## Conventions

- One non-private type per file, named after it. `private` helper views (rows, sheets, glyphs) stay in the file of the screen that owns them — `private` is what says they're not shared. If a second file needs one, drop `private` and move it to its own file rather than widening its access in place.
- Comments are being trimmed: keep only the ones that record something you couldn't work out from the code — a MusicKit quirk, a past bug, a non-obvious invariant. Don't narrate what the code does, don't add a doc comment to every property, and when touching a file remove comments that fail that test rather than preserving them.
- Commit messages are a sentence-case imperative title followed by prose paragraphs explaining the behaviour change and what was wrong before (see `git log`).
- Commit and push directly on `main` unless asked otherwise; there's no PR or branch workflow.
- Unit tests are Swift Testing (`@Test`, `#expect`), not XCTest; only the UI test target uses XCTest.
