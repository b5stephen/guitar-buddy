//
//  MarkerPills.swift
//  MusicMomentum
//

import SwiftData
import SwiftUI

/// A song's markers as a row of pills. Kind is carried by the glyph alone
/// (dot for a point, span for a clip); the fill means only state.
///
/// Everything past the tap is optional, since the saved list has no loop.
struct MarkerPills: View {
    let markers: [SongMarker]
    /// Content margins; the row still scrolls edge to edge.
    var inset: CGFloat = 32
    var leadingInset: CGFloat?
    var isLooping: (SongMarker) -> Bool = { _ in false }
    /// Playhead inside this clip while the loop is off.
    var isCued: (SongMarker) -> Bool = { _ in false }
    var onTap: (SongMarker) -> Void
    var onPlayLoop: ((SongMarker) -> Void)?
    /// The saved list's jump loads the song and changes tab, so it says so.
    var jumpTitle: String = "Jump to Start"
    var onJump: ((SongMarker) -> Void)?
    var onEdit: ((SongMarker) -> Void)?
    var onDelete: ((SongMarker) -> Void)?
    /// When set, the row ends with a Mark pill.
    var onAddMarker: (() -> Void)?

    @ScaledMetric(relativeTo: .footnote) private var dotSize: CGFloat = 6

    private enum PillState {
        case idle, cued, looping
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(markers) { marker in
                    pill(marker)
                }
                if let onAddMarker {
                    markPill(onAddMarker)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.leading, leadingInset ?? inset, for: .scrollContent)
        .contentMargins(.trailing, inset, for: .scrollContent)
    }

    /// The VoiceOver actions hang off here so both branches of `pillControl`
    /// share them.
    private func pill(_ marker: SongMarker) -> some View {
        pillControl(marker)
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(marker, state: state(of: marker)))
            .accessibilityValue(marker.timeLabel)
            .ifLet(marker.isClip ? onPlayLoop : nil) { view, playLoop in
                view.accessibilityAction(named: "Play on loop") { playLoop(marker) }
            }
            .ifLet(onJump) { view, jump in
                view.accessibilityAction(named: jumpTitle) { jump(marker) }
            }
            .ifLet(onEdit) { view, edit in
                view.accessibilityAction(named: "Edit") { edit(marker) }
            }
            .ifLet(onDelete) { view, remove in
                view.accessibilityAction(named: "Delete") { remove(marker) }
            }
    }

    /// A `Menu` with a primary action rather than `.contextMenu`: a context
    /// menu declared inside a `List` row is hoisted to the whole cell, so on
    /// the saved list every pill shared one menu that ran the *first* marker's
    /// actions whichever pill you pressed.
    @ViewBuilder
    private func pillControl(_ marker: SongMarker) -> some View {
        if hasMenu(for: marker) {
            Menu {
                menuItems(marker)
            } label: {
                pillLabel(marker)
            } primaryAction: {
                onTap(marker)
            }
        } else {
            Button { onTap(marker) } label: { pillLabel(marker) }
        }
    }

    private func hasMenu(for marker: SongMarker) -> Bool {
        (marker.isClip && onPlayLoop != nil)
            || onJump != nil
            || onEdit != nil
            || onDelete != nil
    }

    private func pillLabel(_ marker: SongMarker) -> some View {
        let state = state(of: marker)

        return HStack(spacing: 5) {
            glyph(marker)
                .opacity(state == .looping ? 0.8 : 0.55)
            Text(marker.name)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
            if let length = clipLength(marker) {
                Text(length)
                    .font(.footnote.monospacedDigit())
                    .opacity(0.6)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(fill(state), in: Capsule())
        // An overlay stroke so the cued state never changes the pill's size.
        .overlay(Capsule().strokeBorder(.tint, lineWidth: state == .cued ? 1.5 : 0))
        .foregroundStyle(foreground(state))
    }

    @ViewBuilder
    private func menuItems(_ marker: SongMarker) -> some View {
        if let onPlayLoop, marker.isClip {
            Button { onPlayLoop(marker) } label: { Label("Play on Loop", systemImage: "repeat") }
        }
        if let onJump {
            Button { onJump(marker) } label: { Label(jumpTitle, systemImage: "arrow.turn.down.right") }
        }
        if let onEdit {
            Button { onEdit(marker) } label: { Label("Edit", systemImage: "pencil") }
        }
        if let onDelete {
            Button(role: .destructive) { onDelete(marker) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// Outlined rather than filled so it doesn't read as an idle marker.
    private func markPill(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("Mark")
                    .font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .overlay(Capsule().strokeBorder(.tint, lineWidth: 1))
            .foregroundStyle(.tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mark this point")
    }

    @ViewBuilder
    private func glyph(_ marker: SongMarker) -> some View {
        if marker.isClip {
            SpanGlyph()
        } else {
            Circle().frame(width: dotSize, height: dotSize)
        }
    }

    private func clipLength(_ marker: SongMarker) -> String? {
        guard let end = marker.endTime else { return nil }
        return PlaybackScrubber.lengthLabel(max(0, end - marker.startTime))
    }

    private func state(of marker: SongMarker) -> PillState {
        if isLooping(marker) { return .looping }
        return isCued(marker) ? .cued : .idle
    }

    private func fill(_ state: PillState) -> AnyShapeStyle {
        switch state {
        case .idle: AnyShapeStyle(.quaternary)
        case .cued: AnyShapeStyle(.tint.opacity(0.14))
        case .looping: AnyShapeStyle(.tint)
        }
    }

    private func foreground(_ state: PillState) -> AnyShapeStyle {
        switch state {
        case .idle: AnyShapeStyle(.primary)
        case .cued: AnyShapeStyle(.tint)
        case .looping: AnyShapeStyle(.white)
        }
    }

    private func accessibilityLabel(_ marker: SongMarker, state: PillState) -> String {
        let kind = marker.isClip ? "clip" : "marker"
        switch state {
        case .idle: return "\(marker.name), \(kind)"
        case .cued: return "\(marker.name), \(kind), at the playhead"
        case .looping: return "\(marker.name), \(kind), looping"
        }
    }
}

private extension View {
    @ViewBuilder
    func ifLet<T>(_ value: T?, @ViewBuilder transform: (Self, T) -> some View) -> some View {
        if let value { transform(self, value) } else { self }
    }
}

#Preview {
    let container = try! AppSchema.inMemoryContainer()
    let song = SavedSong(songID: "1", speed: 0.8, title: "Little Wing", artistName: "Jimi Hendrix")
    container.mainContext.insert(song)
    SongMarker.add(to: song, name: "Intro", startTime: 4, endTime: nil, in: container.mainContext)
    SongMarker.add(to: song, name: "Verse riff", startTime: 18, endTime: 31, in: container.mainContext)
    SongMarker.add(to: song, name: "Solo", startTime: 96, endTime: 128, in: container.mainContext)
    SongMarker.add(to: song, name: "Outro", startTime: 180, endTime: nil, in: container.mainContext)

    return VStack(spacing: 10) {
        PlaybackScrubber(
            position: 71,
            duration: 245,
            markers: song.sortedMarkers.map {
                .init(
                    id: $0.persistentModelID,
                    start: $0.startTime,
                    end: $0.endTime,
                    isLooping: $0.name == "Solo"
                )
            }
        ) { _ in }
        .padding(.horizontal, 32)

        MarkerPills(
            markers: song.sortedMarkers,
            isLooping: { $0.name == "Solo" },
            isCued: { $0.name == "Verse riff" },
            onTap: { _ in }, onPlayLoop: { _ in }, onJump: { _ in },
            onEdit: { _ in }, onDelete: { _ in }
        )

        MarkerPills(markers: [], onTap: { _ in }, onAddMarker: {})
    }
    .tint(.pink)
    .modelContainer(container)
}
