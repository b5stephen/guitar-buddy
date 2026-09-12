//
//  SavedSongsView.swift
//  GuitarBuddy
//

import MusicKit
import SwiftData
import SwiftUI

/// The practice list: songs the user has put aside, each at the speed they're
/// working on it. Tapping one loads it into the practice tab at that speed.
struct SavedSongsView: View {
    let controller: PlaybackController
    /// Brings the practice tab forward, once a song is on its way to the player.
    let onPractice: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedSong.lastPracticed, order: .reverse)
    private var songs: [SavedSong]

    @State private var showPicker = false
    @State private var editing: SavedSong?
    /// The song being looked up after a tap, so its row can show progress —
    /// resolving an ID back to a `Song` can mean a round trip.
    @State private var loadingID: String?
    /// A lookup that came back empty. Shown here rather than on the practice
    /// screen, which the user never reaches when it fails.
    @State private var lookupError: String?

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
                            showPicker = true
                        } label: {
                            Label("Add Song", systemImage: "music.note.list")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.authorizationStatus != .authorized)
                    }
                } else {
                    List {
                        // A section per song so its markers sit under it as
                        // rows of their own, each with its own swipe-to-delete.
                        ForEach(songs) { song in
                            Section {
                                SavedSongRow(
                                    song: song,
                                    isLoading: loadingID == song.songID,
                                    onPlay: { practice(song) },
                                    onEditSpeed: { editing = song }
                                )
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { delete(song) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }

                                ForEach(song.sortedMarkers) { marker in
                                    MarkerLabel(marker: marker)
                                        .padding(.leading, 60)
                                        .contentShape(Rectangle())
                                        .onTapGesture { practice(song, jumpingTo: marker) }
                                        .accessibilityAction(named: "Practice from here") {
                                            practice(song, jumpingTo: marker)
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { delete(marker) } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
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
                        showPicker = true
                    } label: {
                        Label("Add Song", systemImage: "plus")
                    }
                    .disabled(controller.authorizationStatus != .authorized)
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
            .sheet(item: $editing) { song in
                SpeedEditorSheet(song: song) { speed in
                    save(speed, for: song)
                }
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Actions

    /// Adds a song from the picker. A song that's already on the list keeps the
    /// speed the user tuned it to — adding it again is a way of finding it, not
    /// a request to reset it to 100%.
    private func add(_ song: Song) {
        if let existing = SavedSong.find(songID: song.id.rawValue, in: modelContext) {
            SavedSong.touch(existing, in: modelContext)
        } else {
            SavedSong.save(song: song, speed: 1.0, in: modelContext)
        }
    }

    /// Loads a song into the player, optionally cued up at one of its
    /// markers. The song being on screen already is no shortcut: `select`
    /// resets the playhead, so the jump has to come after it either way.
    /// `select` also drops any loop, so a clip opened from here starts
    /// un-looped until the user turns repeat on.
    private func practice(_ song: SavedSong, jumpingTo marker: SongMarker? = nil) {
        loadingID = song.songID
        Task {
            let found = await controller.select(savedID: song.songID)
            loadingID = nil
            guard found else {
                // Sending the user to a practice screen still showing the last
                // track would look like nothing happened, so say so here.
                lookupError = controller.errorMessage
                return
            }
            if let marker { controller.jump(to: marker) }
            SavedSong.touch(song, in: modelContext)
            onPractice()
        }
    }

    private func save(_ speed: Double, for song: SavedSong) {
        song.speed = speed
        SavedSong.touch(song, in: modelContext)
        // Keep the practice screen honest if this is the song loaded there.
        if controller.selectedSong?.id.rawValue == song.songID {
            controller.playbackRate = speed
        }
    }

    private func delete(_ song: SavedSong) {
        for marker in song.markers { controller.markerDeleted(marker) }
        modelContext.delete(song)
        try? modelContext.save()
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
                    .font(.subheadline)
                    .monospacedDigit()
            }
            // Borderless keeps the pill's tap to itself: a plain button in a
            // `List` row would let the whole row trigger it.
            .buttonStyle(.borderless)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: .capsule)
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
        } else if let url = song.artworkURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder { ProgressView() }
            }
            .frame(width: 48, height: 48)
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

/// The speed wheel from the practice screen, on a sheet, editing one saved
/// song. Changes only land on Done, so a stray spin doesn't rewrite the speed.
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
            VStack(spacing: 12) {
                Text(song.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                SpeedWheelPicker(speed: $speed, diameter: 220)
            }
            .padding()
            .navigationTitle("Practice Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
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
        artworkURL: nil, speed: 0.75, in: context
    )
    let littleWing = SavedSong.save(
        songID: "2", title: "Little Wing", artistName: "Jimi Hendrix",
        artworkURL: nil, speed: 0.6, in: context
    )
    SongMarker.add(to: littleWing, name: "Intro", startTime: 0, endTime: 22, in: context)
    SongMarker.add(to: littleWing, name: "", startTime: 95.5, endTime: nil, in: context)
    SavedSong.save(
        songID: "3", title: "Nothing Else Matters", artistName: "Metallica",
        artworkURL: nil, speed: 1.0, in: context
    )

    return SavedSongsView(controller: PlaybackController()) {}
        .modelContainer(container)
}

#Preview("Empty") {
    SavedSongsView(controller: PlaybackController()) {}
        .modelContainer(try! AppSchema.inMemoryContainer())
}
