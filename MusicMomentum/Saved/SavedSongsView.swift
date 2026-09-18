//
//  SavedSongsView.swift
//  MusicMomentum
//

import MusicKit
import SwiftData
import SwiftUI

struct SavedSongsView: View {
    let controller: PlaybackController
    /// Brings the practice tab forward.
    let onPractice: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedSong.lastPracticed, order: .reverse)
    private var songs: [SavedSong]

    @State private var showPicker = false
    @State private var editing: SavedSong?
    @State private var loadingID: String?
    @State private var lookupError: String?
    @State private var marking: Marking?

    private struct Marking: Identifiable {
        let song: SavedSong
        /// `nil` when adding one.
        let marker: SongMarker?
        let start: TimeInterval

        /// Carries the marker's identity so opening one marker straight after
        /// another rebuilds the sheet.
        var id: String {
            marker.map { "edit-\($0.persistentModelID.hashValue)" }
                ?? "new-\(song.persistentModelID.hashValue)"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView {
                        Label("No saved songs yet", systemImage: "bookmark")
                    } description: {
                        Text("Save a song to practice it again at the speed you left it.")
                    } actions: {
                        Button {
                            chooseSong()
                        } label: {
                            Label("Add Song", systemImage: "music.note.list")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!controller.canUseMusic)
                    }
                } else {
                    // One flat list, not a section per song: section gaps split
                    // a song from its own pills. The separator is drawn by hand
                    // below for the same reason.
                    List {
                        ForEach(songs) { song in
                            SavedSongRow(
                                song: song,
                                isLoading: loadingID == song.songID,
                                onPlay: { practice(song) },
                                onEditSpeed: { editing = song }
                            )
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(song) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                            // Always drawn, so the Mark pill sits in the same
                            // place whether or not the song has markers.
                            MarkerPills(
                                markers: song.sortedMarkers,
                                inset: 16,
                                leadingInset: SavedSongRow.titleInset,
                                // A tap edits here; loading the song is the row
                                // above's job, and still a long press away.
                                onTap: { openEditor(song, marker: $0) },
                                jumpTitle: "Practice From Here",
                                onJump: { practice(song, jumpingTo: $0) },
                                onDelete: { delete($0) },
                                onAddMarker: { openEditor(song) }
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .padding(.bottom, 10)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(.separator)
                                    .frame(height: 0.5)
                                    .padding(.leading, SavedSongRow.titleInset)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Saved")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        chooseSong()
                    } label: {
                        Label("Add Song", systemImage: "plus")
                    }
                    .disabled(!controller.canUseMusic)
                }
            }
            .sheet(isPresented: $showPicker) {
                SongPickerView(onSelect: add)
            }
            .alert(
                "Couldn't open that song",
                isPresented: .init(
                    get: { lookupError != nil },
                    set: { if !$0 { lookupError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(lookupError ?? "")
            }
            .sheet(item: $marking) { marking in
                if let duration = controller.duration {
                    if let marker = marking.marker {
                        MarkerEditorView(
                            marker: marker,
                            duration: duration,
                            controller: controller,
                            onSave: { name, start, end in
                                update(marker, name: name, start: start, end: end)
                            },
                            onDelete: { delete(marker) }
                        )
                    } else {
                        MarkerEditorView(
                            initialStart: marking.start,
                            duration: duration,
                            controller: controller
                        ) { name, start, end in
                            SongMarker.add(
                                to: marking.song,
                                name: name,
                                startTime: start,
                                endTime: end,
                                in: modelContext
                            )
                        }
                    }
                }
            }
            .sheet(item: $editing) { song in
                SpeedEditorSheet(song: song) { speed in
                    save(speed, for: song)
                }
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Actions

    private func chooseSong() {
        Task { showPicker = await controller.requestAuthorizationIfNeeded() }
    }

    /// Re-adding a song keeps its tuned speed rather than resetting to 100%.
    private func add(_ song: Song) {
        if let existing = SavedSong.find(songID: song.id.rawValue, in: modelContext) {
            SavedSong.touch(existing, in: modelContext)
        } else {
            SavedSong.save(song: song, speed: 1.0, in: modelContext)
        }
    }

    /// `select` resets the playhead, so the jump has to come after it even
    /// when the song is already loaded.
    private func practice(_ song: SavedSong, jumpingTo marker: SongMarker? = nil) {
        loadingID = song.songID
        Task {
            // May be the first thing the user does after a reinstall.
            guard await controller.requestAuthorizationIfNeeded() else {
                loadingID = nil
                lookupError = "Allow Apple Music access in Settings to practice this song."
                return
            }
            let found = await controller.select(saved: song)
            loadingID = nil
            guard found else {
                lookupError = controller.errorMessage
                return
            }
            if let marker { controller.jump(to: marker) }
            SavedSong.touch(song, in: modelContext)
            onPractice()
        }
    }

    /// The song has to reach the player first (the editor plays the passage),
    /// but the tab stays put.
    private func openEditor(_ song: SavedSong, marker: SongMarker? = nil) {
        guard controller.selectedSong?.id.rawValue != song.songID else {
            present(song, marker: marker)
            return
        }
        loadingID = song.songID
        Task {
            guard await controller.requestAuthorizationIfNeeded() else {
                loadingID = nil
                lookupError = "Allow Apple Music access in Settings to mark up this song."
                return
            }
            let found = await controller.select(saved: song)
            loadingID = nil
            guard found else {
                lookupError = controller.errorMessage
                return
            }
            present(song, marker: marker)
        }
    }

    private func present(_ song: SavedSong, marker: SongMarker?) {
        guard controller.duration != nil else {
            lookupError = "Apple Music didn't say how long that song is, so it can't be marked up."
            return
        }
        let now = controller.pauseForMarking()
        marking = .init(song: song, marker: marker, start: marker?.startTime ?? now)
    }

    private func save(_ speed: Double, for song: SavedSong) {
        song.speed = speed
        SavedSong.touch(song, in: modelContext)
        if controller.selectedSong?.id.rawValue == song.songID {
            controller.playbackRate = speed
        }
    }

    private func delete(_ song: SavedSong) {
        for marker in song.markers { controller.markerDeleted(marker) }
        modelContext.delete(song)
        try? modelContext.save()
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
}

// MARK: - Row

private struct SavedSongRow: View {
    let song: SavedSong
    let isLoading: Bool
    let onPlay: () -> Void
    let onEditSpeed: () -> Void

    /// Artwork plus gap; the pills and separator line up with it.
    static let titleInset: CGFloat = 76

    var body: some View {
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .lineLimit(1)
                Text(song.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onEditSpeed) {
                Text("\(song.percent)%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
            }
            // A plain button in a `List` row would let the whole row trigger it.
            .buttonStyle(.borderless)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.tint.opacity(0.12), in: .capsule)
            .accessibilityLabel("Speed, \(song.percent) percent")
            .accessibilityHint("Change the practice speed")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Practice", onPlay)
    }

    @ViewBuilder
    private var artwork: some View {
        if isLoading {
            placeholder { ProgressView() }
        } else if let artwork = song.artwork {
            ArtworkImage(artwork, width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 6))
        } else {
            placeholder { Image(systemName: "music.note").foregroundStyle(.secondary) }
        }
    }

    private func placeholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.quaternary)
            .frame(width: 48, height: 48)
            .overlay(content())
    }
}

// MARK: - Speed editor

/// Changes only land on Done, so a stray spin doesn't rewrite the speed.
private struct SpeedEditorSheet: View {
    let song: SavedSong
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var speed: Double

    init(song: SavedSong, onSave: @escaping (Double) -> Void) {
        self.song = song
        self.onSave = onSave
        _speed = State(initialValue: song.speed)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 12) {
                    Text(song.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    SpeedWheelPicker(
                        speed: $speed,
                        diameter: min(260, max(160, proxy.size.width - 130))
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .navigationTitle("Practice Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        onSave(speed)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Saved songs") {
    let container = try! AppSchema.inMemoryContainer()
    let context = ModelContext(container)
    SavedSong.save(
        songID: "1", title: "Blackbird", artistName: "The Beatles",
        artworkData: nil, speed: 0.75, in: context
    )
    let littleWing = SavedSong.save(
        songID: "2", title: "Little Wing", artistName: "Jimi Hendrix",
        artworkData: nil, speed: 0.6, in: context
    )
    SongMarker.add(to: littleWing, name: "Intro", startTime: 0, endTime: 22, in: context)
    SongMarker.add(to: littleWing, name: "", startTime: 95.5, endTime: nil, in: context)
    SavedSong.save(
        songID: "3", title: "Nothing Else Matters", artistName: "Metallica",
        artworkData: nil, speed: 1.0, in: context
    )

    return SavedSongsView(controller: PlaybackController()) {}
        .modelContainer(container)
}

#Preview("Empty") {
    SavedSongsView(controller: PlaybackController()) {}
        .modelContainer(try! AppSchema.inMemoryContainer())
}

#Preview("Speed editor") {
    let container = try! AppSchema.inMemoryContainer()
    let song = SavedSong(songID: "1", speed: 0.75, title: "Blackbird", artistName: "The Beatles")
    container.mainContext.insert(song)

    return SpeedEditorSheet(song: song) { _ in }
        .modelContainer(container)
}
