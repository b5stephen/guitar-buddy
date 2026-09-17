//
//  MarkerPills.swift
//  GuitarBuddy
//

import SwiftData
import SwiftUI

/// A song's markers as a row of small pills, in track order — under the
/// scrubber on the practice screen, under the song on the saved list.
///
/// Every pill is the same capsule, whatever it is and whatever it's doing.
/// Kind is carried by the glyph alone — a dot for a point, a span bar for a
/// clip — so a row of mixed markers reads as one set of objects rather than
/// two competing ones, and the fill is left free to mean only state: idle,
/// cued under the playhead, or lit because it's in the running loop.
///
/// Everything past the tap is optional, since the saved list can't loop or
/// edit a song that isn't loaded — a pill there just opens the song at that
/// spot, with delete on a long press.
struct MarkerPills: View {
    let markers: [SongMarker]
    /// Leading and trailing inset, to line the row up with whatever it sits
    /// under. The row still scrolls edge to edge.
    var inset: CGFloat = 32
    /// Overrides the leading inset, for a row that follows something pinned
    /// outside it and needs only a gap rather than the full margin.
    var leadingInset: CGFloat?
    /// Whether this clip is in the running loop's scope, so the pill can show
    /// it lit.
    var isLooping: (SongMarker) -> Bool = { _ in false }
    /// Whether the playhead is sitting inside this clip while the loop is off
    /// — the clip you'd be drilling if you turned the loop on.
    var isCued: (SongMarker) -> Bool = { _ in false }
    /// Tapping a point jumps to it. Tapping a clip jumps to its start too,
    /// unless a loop is running, in which case it goes in or out of scope.
    var onTap: (SongMarker) -> Void
    /// Loops this clip alone and starts playing it. Clips only, and absent
    /// wherever there's no loaded song to play.
    var onPlayLoop: ((SongMarker) -> Void)?
    var onJump: ((SongMarker) -> Void)?
    var onEdit: ((SongMarker) -> Void)?
    var onDelete: ((SongMarker) -> Void)?
    /// Adds a marker to this song. When it's there the row ends with a Mark
    /// pill, so a song with no markers at all still offers the row's one
    /// useful action in the place the markers would be.
    var onAddMarker: (() -> Void)?

    /// Scaled with the label beside it, for the same reason the span bar is.
    @ScaledMetric(relativeTo: .footnote) private var dotSize: CGFloat = 6

    /// How a pill is drawn. The kind doesn't come into it — that's the glyph.
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

    private func pill(_ marker: SongMarker) -> some View {
        let state = state(of: marker)

        return Button {
            onTap(marker)
        } label: {
            HStack(spacing: 5) {
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
            // Stroked rather than bordered so joining the loop never changes
            // the pill's size and reflows the row around it.
            .overlay(Capsule().strokeBorder(.tint, lineWidth: state == .cued ? 1.5 : 0))
            .foregroundStyle(foreground(state))
        }
        .buttonStyle(.plain)
        .contextMenu {
            // First, and above Jump: it's the stronger form of the same
            // intent, and the quickest way to drill one clip.
            if let onPlayLoop, marker.isClip {
                Button { onPlayLoop(marker) } label: { Label("Play on Loop", systemImage: "repeat") }
            }
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
        .accessibilityLabel(accessibilityLabel(marker, state: state))
        .accessibilityValue(marker.timeLabel)
        .ifLet(marker.isClip ? onPlayLoop : nil) { view, playLoop in
            view.accessibilityAction(named: "Play on loop") { playLoop(marker) }
        }
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

    /// The row's tail. Outlined rather than filled, because it isn't a marker
    /// — it's the invitation to make one, and it shouldn't read as an idle
    /// pill sitting among the real ones.
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

    /// A clip says how long it is; a point has no length to say. Seconds up to
    /// a minute, because "45s" is the number you compare passages on, and m:ss
    /// past that where seconds alone stop being readable.
    private func clipLength(_ marker: SongMarker) -> String? {
        guard let end = marker.endTime else { return nil }
        let length = max(0, end - marker.startTime)
        return length < 60
            ? "\(Int(length.rounded()))s"
            : PlaybackScrubber.timeLabel(length)
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

/// The clip glyph: a rule between two uprights, the shape a passage makes on
/// the track above. Drawn rather than borrowed from SF Symbols, none of which
/// reads as a span at this size without also reading as an arrow.
struct SpanGlyph: View {
    /// Tied to the label beside it, because the glyph is now the only thing
    /// telling a clip from a point: a 10pt mark next to accessibility-sized
    /// type would give that difference away exactly where it's needed most.
    @ScaledMetric(relativeTo: .footnote) private var width: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 10
            var path = Path()
            path.move(to: CGPoint(x: 1 * scale, y: 1 * scale))
            path.addLine(to: CGPoint(x: 1 * scale, y: 7 * scale))
            path.move(to: CGPoint(x: 9 * scale, y: 1 * scale))
            path.addLine(to: CGPoint(x: 9 * scale, y: 7 * scale))
            path.move(to: CGPoint(x: 1 * scale, y: 4 * scale))
            path.addLine(to: CGPoint(x: 9 * scale, y: 4 * scale))
            context.stroke(
                path,
                with: .style(.foreground),
                style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round)
            )
        }
        .frame(width: width, height: width * 0.8)
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
