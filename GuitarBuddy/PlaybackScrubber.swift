//
//  PlaybackScrubber.swift
//  GuitarBuddy
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The Apple Music-style position bar: a thin track that thickens under your
/// finger, elapsed time on the left, time remaining on the right.
///
/// Scrubbing is deliberately *not* wired straight through to the player. The
/// bar reports a live position while the finger is down so the labels track
/// it, and only commits a seek on release — one seek per gesture instead of
/// sixty, which keeps the audio from stuttering as you drag.
struct PlaybackScrubber: View {
    /// Where the playhead is, in seconds.
    let position: TimeInterval
    /// Track length. Nothing to scrub without one, so the bar goes inert.
    let duration: TimeInterval?
    /// The song's markers, drawn on the track so the pills below have
    /// somewhere to point at.
    var markers: [Marker] = []
    /// Called continuously with the finger's position while dragging.
    var onScrub: (TimeInterval) -> Void = { _ in }
    /// Called once with the final position when the finger lifts.
    var onCommit: (TimeInterval) -> Void

    /// A marker's footprint on the bar: a hairline for a point, a shaded
    /// band between the two times for a clip.
    struct Marker: Identifiable {
        let id: AnyHashable
        let start: TimeInterval
        let end: TimeInterval?
    }

    /// Live drag position. Non-nil only while a finger is down, and it — not
    /// `position` — is what the bar draws, so the thumb never snaps back to a
    /// stale playhead between the release and the player catching up.
    @State private var dragPosition: TimeInterval?

    private var isDragging: Bool { dragPosition != nil }
    private var displayedPosition: TimeInterval { dragPosition ?? position }

    private var fraction: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(max(displayedPosition / duration, 0), 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            bar
            labels
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(Text(Self.timeLabel(displayedPosition)))
        .accessibilityAdjustableAction { direction in
            guard duration != nil else { return }
            let step: TimeInterval = direction == .increment ? 5 : -5
            onCommit(displayedPosition + step)
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height: CGFloat = isDragging ? 10 : 6

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(.tint)
                    .frame(width: max(height, width * fraction))
                markerOverlay(width: width, height: height)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            // A 44pt-tall hit area over a 6pt bar: the bar is the drawing,
            // this is the target.
            .contentShape(.rect)
            .gesture(dragGesture(width: width))
            .animation(.snappy(duration: 0.2), value: isDragging)
        }
        .frame(height: 44)
        .disabled(duration == nil)
    }

    /// Points and clips on the track. Drawn over the fill in a neutral ink so
    /// they stay legible on both the played and unplayed halves of the bar.
    @ViewBuilder
    private func markerOverlay(width: CGFloat, height: CGFloat) -> some View {
        if let duration, duration > 0 {
            ForEach(markers) { marker in
                let x = width * min(max(marker.start / duration, 0), 1)
                if let end = marker.end {
                    let span = width * min(max((end - marker.start) / duration, 0), 1)
                    Capsule()
                        .fill(.primary.opacity(0.22))
                        .frame(width: max(2, span), height: height)
                        .offset(x: x)
                } else {
                    Capsule()
                        .fill(.primary.opacity(0.45))
                        .frame(width: 2, height: height)
                        .offset(x: max(0, x - 1))
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let duration, duration > 0, width > 0 else { return }
                if dragPosition == nil {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    #endif
                }
                let time = duration * min(max(value.location.x / width, 0), 1)
                dragPosition = time
                onScrub(time)
            }
            .onEnded { _ in
                guard let time = dragPosition else { return }
                dragPosition = nil
                onCommit(time)
            }
    }

    private var labels: some View {
        HStack {
            Text(Self.timeLabel(displayedPosition))
            Spacer()
            if let duration {
                Text("-" + Self.timeLabel(max(0, duration - displayedPosition)))
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    /// `m:ss`, growing to `h:mm:ss` only when a track actually runs that long.
    nonisolated static func timeLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

#Preview {
    PlaybackScrubber(
        position: 71,
        duration: 245,
        markers: [
            .init(id: "intro", start: 12, end: nil),
            .init(id: "solo", start: 96, end: 128)
        ]
    ) { _ in }
        .tint(.pink)
        .padding()
}
