//
//  ContentView.swift
//  GuitarBuddy
//

import MusicKit
import SwiftData
import SwiftUI

struct ContentView: View {
    /// Owned by `RootTabView`, since the saved list drives it too. `@Bindable`
    /// rather than `let` so the speed wheel can still bind to `playbackRate`.
    @Bindable var controller: PlaybackController

    @Environment(\.scenePhase) private var scenePhase
    @Query private var savedSongs: [SavedSong]
    @State private var showPicker = false

    var body: some View {
        // The content is short enough to fit on most screens, so it sits
        // centred; `minHeight` keeps it scrollable on the ones where it
        // doesn't (small phones, large text).
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    nowPlaying

                    Button {
                        showPicker = true
                    } label: {
                        Label("Choose Song", systemImage: "music.note.list")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.authorizationStatus != .authorized)

                    if controller.selectedSong != nil {
                        SpeedWheelPicker(speed: $controller.playbackRate)
                            .padding(.horizontal)

                        PlaybackScrubber(
                            position: controller.playbackTime,
                            duration: controller.duration,
                            onScrub: { _ in controller.isScrubbing = true },
                            onCommit: { controller.endScrub(at: $0) }
                        )
                        // Wider than the usual 16pt: the bar spans the full
                        // width, so it needs more breathing room off the edges
                        // than the centred content above it.
                        .padding(.horizontal, 32)

                        transportControls
                    }

                    messages
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .sheet(isPresented: $showPicker) {
            SongPickerView { song in
                Task { await controller.select(song: song) }
            }
        }
        .task {
            await controller.requestAuthorizationIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            // The ticker was idle while we were backgrounded, so the playhead
            // needs one read to catch up.
            if phase == .active { controller.refreshPlaybackTime() }
        }
    }

    /// Restart, skip back, play/pause, skip forward — the moves you make over
    /// and over when drilling a passage, all reachable with one thumb.
    private var transportControls: some View {
        HStack(spacing: 28) {
            transportButton("gobackward", label: "Restart") {
                controller.restart()
            }
            transportButton("gobackward.10", label: "Back 10 seconds") {
                controller.skip(by: -10)
            }

            Button {
                controller.togglePlayPause()
            } label: {
                Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")

            transportButton("goforward.10", label: "Forward 10 seconds") {
                controller.skip(by: 10)
            }

            // Balances the restart button on the left so play/pause sits dead
            // centre rather than drifting right.
            transportButton("gobackward", label: "") {}
                .hidden()
        }
    }

    private func transportButton(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 26))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var nowPlaying: some View {
        if let song = controller.selectedSong {
            VStack(spacing: 4) {
                Text(song.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(song.artistName)
                    .foregroundStyle(.secondary)

                saveButton
                    .padding(.top, 4)
            }
            .padding(.horizontal)
        } else if controller.authorizationStatus == .authorized {
            ContentUnavailableView(
                "No song selected",
                systemImage: "music.note",
                description: Text("Pick a track from Apple Music to practice with.")
            )
        } else {
            ContentUnavailableView(
                "Apple Music access needed",
                systemImage: "lock",
                description: Text(authorizationHint)
            )
        }
    }

    /// Puts the current speed on the practice list. Deliberately not a toolbar
    /// item: this screen has no `NavigationStack`, and its layout is tuned to
    /// fit one screen. The label names the speed so the button says what it
    /// will do without needing a confirmation step.
    @ViewBuilder
    private var saveButton: some View {
        let percent = Int((controller.playbackRate * 100).rounded())
        let saved = savedSong

        Button {
            controller.saveCurrentSong()
        } label: {
            if let saved, saved.percent == percent {
                Label("Saved at \(percent)%", systemImage: "bookmark.fill")
            } else if saved != nil {
                Label("Update to \(percent)%", systemImage: "bookmark.fill")
            } else {
                Label("Save at \(percent)%", systemImage: "bookmark")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(saved?.percent == percent)
    }

    /// The saved entry for the song on screen, if it's on the list. Reads the
    /// `@Query` results rather than fetching, so the button restyles itself the
    /// moment the store changes — including from the Saved tab.
    private var savedSong: SavedSong? {
        guard let songID = controller.selectedSong?.id.rawValue else { return nil }
        return savedSongs.first { $0.songID == songID }
    }

    @ViewBuilder
    private var messages: some View {
        VStack(spacing: 8) {
            if let warning = controller.rateWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let error = controller.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }

    private var authorizationHint: String {
        switch controller.authorizationStatus {
        case .denied, .restricted:
            "Allow Apple Music access in Settings to pick and slow down songs."
        default:
            "Guitar Buddy needs permission to use your Apple Music library."
        }
    }
}

#Preview {
    ContentView(controller: PlaybackController())
        .modelContainer(try! AppSchema.inMemoryContainer())
}
