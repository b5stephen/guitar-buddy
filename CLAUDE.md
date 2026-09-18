# CLAUDE.md

## Commands

```sh
xcodebuild build -scheme MusicMomentum -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
xcodebuild test  -scheme MusicMomentum -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MusicMomentumTests
# narrower: -only-testing:MusicMomentumTests/LoopChainTests[/testName]
```

The simulator must run iOS ≥ 26.4 or the build is rejected with "doesn't match deployment target"; `xcrun simctl list devices available` if the one above is gone. Playback, `SongLookup` and the pickers need a real device with a subscription; the simulator builds and runs unit tests only, and unit tests must never need MusicKit.

## Layout

`App/` entry point and tab shell · `Model/` SwiftData models · `Music/` everything that talks to MusicKit outside the UI · one folder per screen (`Practice/`, `Saved/`), with a flow only one screen presents nested inside it (`Practice/SongPicker/`). Promote a nested flow when a second screen presents it. No `Components/`, `Utilities/` or `Helpers/` folder until two screens actually share something, and then name the folder for what it holds, not for being shared. Folders are Xcode synchronized groups, so moving a file on disk is the whole job. Tests mirror `Model/` and `Music/`. Don't list screens here; the folder is the documentation.

## Rules the code can't enforce

- `RootTabView` owns the one `PlaybackController`; it's the only thing that talks to `ApplicationMusicPlayer`. Its comments record MusicKit quirks (seek settling, unplayed queues dropping writes, rate changes starting a paused player) — read them before changing it.
- Choosing something (a song, a marker) never starts playback. The one exception is "Play on Loop", and the comment there explains why.
- Only the loop button turns looping on or off; pills reshape scope, and running out of clips widens to whole-song rather than stopping.
- Speeds are persisted only on explicit save, never from `playbackRate`'s `didSet`.
- All model mutation goes through `SongMarker.add/set/clearEnd/delete` and `SavedSong.save/touch`, which enforce the invariants and save. New models go in `AppSchema.models`; the app, previews and tests all build from it.
- Storage APIs take plain values, with a `Song` overload on top, because `Song`/`Artwork` have no public initialisers and tests can't construct them.

## Conventions

- One non-private type per file, named after it. `private` helper views stay with the screen that owns them; if a second file needs one, drop `private` and move it to its own file.
- Comments record only what the code can't say — a MusicKit quirk, a past bug, a non-obvious invariant. Don't narrate the code; when touching a file, delete comments that fail that test.
- Unit tests are Swift Testing (`@Test`, `#expect`, `@MainActor @Suite`), each building its own in-memory `ModelContext` in `init()`. Only the UI test target uses XCTest.
- Commit messages: sentence-case imperative title, then prose paragraphs on the behaviour change and what was wrong before (see `git log`). Commit and push directly on `main`.
