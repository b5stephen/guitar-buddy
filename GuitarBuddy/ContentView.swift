//
//  ContentView.swift
//  GuitarBuddy
//

import MusicKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = PlaybackController()
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
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
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Guitar Buddy")
            .sheet(isPresented: $showPicker) {
                SongPickerView(selection: $controller.selectedSong)
            }
            .task {
                controller.configure(modelContext: modelContext)
                await controller.requestAuthorizationIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                // Transport may have moved while we were backgrounded.
                if phase == .active { controller.syncPlaybackState() }
            }
            .task(id: controller.selectedSong) {
                if let song = controller.selectedSong {
                    await controller.play(song: song)
                }
            }
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
            VStack(spacing: 10) {
                if let artwork = song.artwork {
                    ArtworkImage(artwork, width: 160, height: 160)
                        .clipShape(.rect(cornerRadius: 12))
                }
                Text(song.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(song.artistName)
                    .foregroundStyle(.secondary)
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
    ContentView()
        .modelContainer(for: SongSpeedPreference.self, inMemory: true)
}
