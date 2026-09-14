//
//  MarkerPills.swift
//  GuitarBuddy
//

import SwiftData
import SwiftUI

/// A song's markers as a row of small pills, in track order — under the
/// scrubber on the practice screen, under the song on the saved list. Just
/// the names: on the practice screen the times are already drawn on the bar
/// above, as ticks for points and shaded bands for clips.
///
/// Shape carries the kind, so the two read apart at a glance and without
/// relying on colour: a point is a round-ended capsule with a pin, a clip is
/// a squared-off pill with a span arrow, the way a passage looks.
///
/// Everything past the tap is optional, since the saved list can't loop or
/// edit a song that isn't loaded — a pill there just opens the song at that
/// spot, with delete on a long press.
struct MarkerPills: View {
    let markers: [SongMarker]
    /// Leading and trailing inset, to line the row up with whatever it sits
    /// under. The row still scrolls edge to edge.
    var inset: CGFloat = 32
    /// Whether this clip's loop is armed, so the pill can show it running.
    var isLooping: (SongMarker) -> Bool = { _ in false }
    /// Tapping a point jumps to it; tapping a clip arms or disarms its loop.
    var onTap: (SongMarker) -> Void
    var onJump: ((SongMarker) -> Void)?
    var onEdit: ((SongMarker) -> Void)?
    var onDelete: ((SongMarker) -> Void)?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(markers) { marker in
                    pill(marker)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, inset, for: .scrollContent)
    }

    private func pill(_ marker: SongMarker) -> some View {
        let looping = isLooping(marker)

        return Button {
            onTap(marker)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: glyph(marker, looping: looping))
                    .font(.caption2)
                    .symbolEffect(.pulse, isActive: looping)
                Text(marker.name)
                    .lineLimit(1)
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(background(marker, looping: looping), in: shape(marker))
            .overlay(shape(marker).strokeBorder(.tint.opacity(marker.isClip && !looping ? 0.5 : 0)))
            .foregroundStyle(looping ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onJump {
                Button { onJump(marker) } label: { Label("Jump to Start", systemImage: "arrow.turn.down.right") }
            }
            if let onEdit {
                Button { onEdit(marker) } label: { Label("Edit", systemImage: "pencil") }
            }
            if let onDelete {
                Button(role: .destructive) { onDelete(marker) } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .accessibilityLabel(accessibilityLabel(marker, looping: looping))
        .accessibilityValue(marker.timeLabel)
        .ifLet(onJump) { view, jump in
            view.accessibilityAction(named: "Jump to start") { jump(marker) }
        }
        .ifLet(onEdit) { view, edit in
            view.accessibilityAction(named: "Edit") { edit(marker) }
        }
        .ifLet(onDelete) { view, remove in
            view.accessibilityAction(named: "Delete") { remove(marker) }
        }
    }

    /// Capsule for a point, rounded rect for a clip: a span has ends. Both
    /// are rounded rects so the pill can stroke one shape — a radius past
    /// half the pill's height rounds all the way to a capsule anyway.
    private func shape(_ marker: SongMarker) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: marker.isClip ? 7 : 100, style: .continuous)
    }

    private func glyph(_ marker: SongMarker, looping: Bool) -> String {
        if looping { return "repeat" }
        return marker.isClip ? "arrow.left.and.right" : "mappin"
    }

    private func background(_ marker: SongMarker, looping: Bool) -> AnyShapeStyle {
        if looping { return AnyShapeStyle(.tint) }
        return marker.isClip
            ? AnyShapeStyle(.tint.opacity(0.15))
            : AnyShapeStyle(.quaternary)
    }

    private func accessibilityLabel(_ marker: SongMarker, looping: Bool) -> String {
        let kind = marker.isClip ? (looping ? "clip, looping" : "clip") : "marker"
        return "\(marker.name), \(kind)"
    }
}

private extension View {
    /// Applies a modifier only when its optional input is there — for the
    /// accessibility actions that exist only where the caller handles them.
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
                .init(id: $0.persistentModelID, start: $0.startTime, end: $0.endTime)
            }
        ) { _ in }
        .padding(.horizontal, 32)

        MarkerPills(
            markers: song.sortedMarkers,
            isLooping: { $0.name == "Solo" },
            onTap: { _ in }, onJump: { _ in }, onEdit: { _ in },
            onDelete: { _ in }
        )
    }
    .tint(.pink)
    .modelContainer(container)
}
