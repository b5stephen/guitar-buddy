//
//  PlaybackScrubber.swift
//  MusicMomentum
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Position bar with the markers drawn on it. Only commits a seek on release
/// — one per gesture, not sixty — so the audio doesn't stutter while dragging.
struct PlaybackScrubber: View {
    let position: TimeInterval
    /// Inert when `nil`.
    let duration: TimeInterval?
    var markers: [Marker] = []
    var onScrub: (TimeInterval) -> Void = { _ in }
    var onCommit: (TimeInterval) -> Void

    struct Marker: Identifiable {
        let id: AnyHashable
        let start: TimeInterval
        let end: TimeInterval?
        var isLooping: Bool = false

        var isClip: Bool { end != nil }
    }

    /// What the bar draws while a finger is down, so the thumb never snaps
    /// back to a stale playhead before the player catches up.
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
                    .fill(.tint.opacity(0.45))
                    .frame(width: max(height, width * fraction))
                markerOverlay(width: width, height: height)
                playhead(width: width, height: height)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(dragGesture(width: width))
            .animation(.snappy(duration: 0.2), value: isDragging)
        }
        .frame(height: 44)
        .disabled(duration == nil)
    }

    /// Looping bands are ringed in the background colour so the played fill,
    /// in the same tint, can't swallow them.
    @ViewBuilder
    private func markerOverlay(width: CGFloat, height: CGFloat) -> some View {
        if let duration, duration > 0 {
            ForEach(markers) { marker in
                let x = width * min(max(marker.start / duration, 0), 1)
                if let end = marker.end {
                    let span = width * min(max((end - marker.start) / duration, 0), 1)
                    if marker.isLooping {
                        ZStack {
                            Capsule()
                                .fill(.background)
                                .frame(width: max(2, span) + 4, height: 18)
                            Capsule()
                                .fill(.tint)
                                .frame(width: max(2, span), height: 14)
                        }
                        .offset(x: x)
                    } else {
                        Capsule()
                            .fill(.primary.opacity(0.25))
                            .frame(width: max(2, span), height: height)
                            .offset(x: x)
                    }
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

    /// Hollow so it stays visible on top of a lit loop band.
    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(.background)
            .overlay(Capsule().strokeBorder(.primary.opacity(0.25), lineWidth: 1.5))
            .frame(width: 6, height: max(14, height + 8))
            .offset(x: min(max(0, width * fraction - 3), max(0, width - 6)))
            .allowsHitTesting(false)
            .opacity(duration == nil ? 0 : 1)
    }

    private func fraction(of marker: Marker) -> Double {
        guard let duration, duration > 0 else { return 0 }
        return min(max(marker.start / duration, 0), 1)
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

    /// `m:ss`, or `h:mm:ss` when needed.
    nonisolated static func timeLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// `45s` under a minute, `m:ss` past it.
    nonisolated static func lengthLabel(_ seconds: TimeInterval) -> String {
        seconds < 60
            ? "\(Int(seconds.rounded()))s"
            : timeLabel(seconds)
    }
}

#Preview("A few markers") {
    PlaybackScrubber(
        position: 71,
        duration: 245,
        markers: [
            .init(id: "intro", start: 4, end: nil),
            .init(id: "verse", start: 40, end: 71),
            .init(id: "solo", start: 96, end: 128, isLooping: true),
            .init(id: "outro", start: 238, end: nil)
        ]
    ) { _ in }
        .padding(.horizontal, 32)
}

// The case the halo around a lit band is there for.
#Preview("Looping, already played") {
    PlaybackScrubber(
        position: 190,
        duration: 245,
        markers: [
            .init(id: "intro", start: 4, end: nil),
            .init(id: "verse", start: 40, end: 71),
            .init(id: "solo", start: 96, end: 128, isLooping: true),
            .init(id: "outro", start: 238, end: nil)
        ]
    ) { _ in }
        .padding(.horizontal, 32)
}

#Preview("A songful of markers") {
    PlaybackScrubber(
        position: 110,
        duration: 245,
        markers: (0..<8).map {
            .init(
                id: $0,
                start: TimeInterval($0) * 28 + 4,
                end: $0.isMultiple(of: 2) ? TimeInterval($0) * 28 + 22 : nil,
                isLooping: $0 == 4
            )
        }
    ) { _ in }
        .padding(.horizontal, 32)
}
