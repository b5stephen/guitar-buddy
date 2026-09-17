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
    @Environment(\.modelContext) private var modelContext
    @Query private var savedSongs: [SavedSong]
    @State private var showPicker = false
    @State private var markerSheet: MarkerSheet?

    /// What the marker sheet is open for. `Identifiable` so `.sheet(item:)`
    /// can drive it; editing gets the marker's own identity so switching
    /// straight from one marker to another rebuilds the sheet.
    private enum MarkerSheet: Identifiable {
        case new(start: TimeInterval)
        case edit(SongMarker)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let marker): "edit-\(marker.persistentModelID.hashValue)"
            }
        }
    }

    var body: some View {
        // The content is short enough to fit on most screens, so it sits
        // centred; `minHeight` keeps it scrollable on the ones where it
        // doesn't (small phones, large text).
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    nowPlaying

                    Button {
                        // Asking here, rather than at launch, means the system
                        // prompt lands on the tap that needs it.
                        Task { showPicker = await controller.requestAuthorizationIfNeeded() }
                    } label: {
                        Label("Choose Song", systemImage: "music.note.list")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!controller.canUseMusic)

                    if controller.selectedSong != nil {
                        SpeedWheelPicker(speed: $controller.playbackRate)
                            .padding(.horizontal)

                        VStack(spacing: 10) {
                            PlaybackScrubber(
                                position: controller.playbackTime,
                                duration: controller.duration,
                                markers: scrubberMarkers,
                                onScrub: { _ in controller.isScrubbing = true },
                                onCommit: { controller.endScrub(at: $0) }
                            )
                            // Wider than the usual 16pt: the bar spans the full
                            // width, so it needs more breathing room off the
                            // edges than the centred content above it.
                            .padding(.horizontal, 32)

                            loopRow
                        }

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
        .sheet(item: $markerSheet) { sheet in
            if let duration = controller.duration {
                switch sheet {
                case .new(let start):
                    MarkerEditorView(
                        initialStart: start,
                        duration: duration,
                        controller: controller,
                        onSave: addMarker
                    )
                case .edit(let marker):
                    MarkerEditorView(
                        marker: marker,
                        duration: duration,
                        controller: controller,
                        onSave: { name, start, end in update(marker, name: name, start: start, end: end) },
                        onDelete: { delete(marker) }
                    )
                }
            }
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

            // Sits opposite restart so play/pause stays dead centre.
            transportButton("flag", label: "Mark this point") {
                markerSheet = .new(start: controller.pauseForMarking())
            }
            .disabled(controller.duration == nil)
        }
    }

    // MARK: - Markers

    /// The loop button and the song's markers on one row: the button is the
    /// master switch, the pills are its scope. Putting them together is what
    /// teaches the rule — nothing lit while the button is on means the whole
    /// song. The button sits outside the scroll view so a long row of pills
    /// can never push it out of reach.
    private var loopRow: some View {
        HStack(spacing: 8) {
            loopButton

            if let saved = savedSong, !saved.markers.isEmpty {
                MarkerPills(
                    markers: saved.sortedMarkers,
                    leadingInset: 8,
                    isLooping: { controller.isLooping($0) },
                    loopOrdinal: { controller.loopOrdinal($0) },
                    onTap: { tapped($0) },
                    onPlayLoop: { controller.playOnLoop($0) },
                    onJump: { controller.jump(to: $0) },
                    onEdit: { markerSheet = .edit($0) },
                    onDelete: { delete($0) }
                )
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 32)
    }

    /// Turns looping on and off — the only control that does. With the button
    /// on and no clips lit it's the whole track, which is what you want when
    /// you're learning a song rather than drilling a passage.
    private var loopButton: some View {
        Button {
            controller.toggleLoop()
        } label: {
            // Built like a pill rather than as a Label, so the glyph, the
            // weights and the paddings match the row it heads exactly.
            HStack(spacing: 5) {
                Image(systemName: "repeat")
                    .font(.caption2)
                    .symbolEffect(.pulse, isActive: controller.isLoopOn)
                Text("Loop")
            }
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    controller.isLoopOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    in: Capsule()
                )
                .foregroundStyle(controller.isLoopOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Loop")
        .accessibilityValue(loopDescription)
        .accessibilityAddTraits(controller.isLoopOn ? .isSelected : [])
    }

    /// What the loop button is currently looping, for VoiceOver — the pills
    /// carry this visually, but they're a separate element to the button.
    private var loopDescription: String {
        guard let loop = controller.loop else { return "Off" }
        let clips = loop.segments.count
        switch clips {
        case 0: return "Whole song"
        case 1: return "One clip"
        default: return "\(clips) clips"
        }
    }

    /// A pill tap. With the loop off it's navigation, points and clips alike.
    /// With it on, a clip goes in or out of the loop's scope instead — the
    /// context menu's Jump to Start is there when you want to move without
    /// reshaping a running loop.
    private func tapped(_ marker: SongMarker) {
        if controller.isLoopOn, marker.isClip {
            controller.toggleLoop(for: marker)
        } else {
            controller.jump(to: marker)
        }
    }

    /// The same markers, as the footprints the scrubber draws on its track.
    private var scrubberMarkers: [PlaybackScrubber.Marker] {
        (savedSong?.sortedMarkers ?? []).map {
            .init(id: $0.persistentModelID, start: $0.startTime, end: $0.endTime)
        }
    }

    /// Marking a song puts it on the saved list if it isn't there yet —
    /// markers live on the saved entry, and a mark you couldn't get back to
    /// would be no use.
    private func addMarker(name: String, start: TimeInterval, end: TimeInterval?) {
        guard let song = savedSong ?? controller.saveCurrentSong() else { return }
        SongMarker.add(to: song, name: name, startTime: start, endTime: end, in: modelContext)
    }

    private func update(_ marker: SongMarker, name: String, start: TimeInterval, end: TimeInterval?) {
        marker.set(name: name, start: start, end: end)
        try? modelContext.save()
        controller.markerChanged(marker)
    }

    private func delete(_ marker: SongMarker) {
        controller.markerDeleted(marker)
        SongMarker.delete(marker, in: modelContext)
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
        } else if controller.canUseMusic {
            ContentUnavailableView(
                "No song selected",
                systemImage: "music.note",
                description: Text("Pick a track from Apple Music to practice with.")
            )
        } else {
            ContentUnavailableView(
                "Apple Music access needed",
                systemImage: "lock",
                description: Text("Allow Apple Music access in Settings to pick and slow down songs.")
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
}

#Preview {
    ContentView(controller: PlaybackController())
        .modelContainer(try! AppSchema.inMemoryContainer())
}
