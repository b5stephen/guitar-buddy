//
//  MarkerRangeEditor.swift
//  GuitarBuddy
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A big, zoomable strip of the track with a drag handle for a marker's start
/// and, when it has one, its end.
///
/// There's no waveform: Apple Music tracks are DRM-protected and neither
/// MusicKit nor `MPMediaItem` gives out their samples. What makes a point easy
/// to land is zoom instead — across the whole of a four-minute song one point
/// on screen is most of a second, but in the 5-second window it's about 15ms.
/// In a zoomed window, dragging anywhere that isn't a handle pans.
///
/// Times come and go through the bindings; the strip never touches the player.
struct MarkerRangeEditor: View {
    @Binding var start: TimeInterval
    @Binding var end: TimeInterval?
    let duration: TimeInterval
    /// Drawn as a thin line so the user can see where the song is relative to
    /// the handles after an audition.
    let playhead: TimeInterval

    enum Zoom: String, CaseIterable, Identifiable {
        case whole = "Song", thirty = "30s", five = "5s"
        var id: String { rawValue }
        /// Seconds visible across the strip; `nil` for the whole track.
        var span: TimeInterval? {
            switch self {
            case .whole: nil
            case .thirty: 30
            case .five: 5
            }
        }
    }

    @State private var zoom: Zoom = .whole
    /// Left edge of the visible window, in seconds.
    @State private var windowStart: TimeInterval = 0
    @State private var drag: Drag?

    private enum Drag {
        case start, end
        /// Pan, remembering where the window was when the finger went down.
        case pan(from: TimeInterval)
        /// A drag that started in the open on the whole-song view, where
        /// there's nothing to pan. Swallowed rather than moving a handle
        /// the user didn't touch.
        case nothing
    }

    /// How close, in points, a finger has to land to a handle to grab it.
    private static let grabRadius: CGFloat = 28
    private static let barHeight: CGFloat = 64
    private static let labelHeight: CGFloat = 18

    private var span: TimeInterval {
        min(zoom.span ?? duration, duration)
    }

    private var window: ClosedRange<TimeInterval> {
        windowStart...(windowStart + span)
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Zoom", selection: $zoom) {
                ForEach(Zoom.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            strip
                .frame(height: Self.barHeight + Self.labelHeight + 8)
        }
        .onAppear { recentre() }
        .onChange(of: zoom) { recentre() }
        // Steppers and the typed fields can push a handle out of view.
        .onChange(of: start) { if !window.contains(start) { recentre() } }
        .onChange(of: end) { if let end, !window.contains(end) { recentre() } }
        // The steppers and time fields carry the same values for VoiceOver;
        // a two-handle drag strip has no good spoken form.
        .accessibilityHidden(true)
    }

    private var strip: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .topLeading) {
                if let end {
                    let left = x(start, width: width)
                    let right = x(end, width: width)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .frame(height: Self.barHeight)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(.tint)
                                .opacity(0.3)
                                .frame(width: max(0, right - left))
                                .offset(x: left)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .frame(height: Self.barHeight)
                }

                ticks(width: width)

                if window.contains(playhead) {
                    Rectangle()
                        .fill(.secondary)
                        .frame(width: 1, height: Self.barHeight)
                        .offset(x: x(playhead, width: width))
                }

                handle(at: x(start, width: width), filled: true)
                if let end {
                    handle(at: x(end, width: width), filled: false)
                }
            }
            .contentShape(.rect)
            .gesture(dragGesture(width: width))
        }
    }

    private func handle(at position: CGFloat, filled: Bool) -> some View {
        VStack(spacing: 0) {
            Circle()
                .fill(filled ? AnyShapeStyle(.tint) : AnyShapeStyle(.background))
                .overlay(Circle().strokeBorder(.tint, lineWidth: 3))
                .frame(width: 22, height: 22)
                .shadow(radius: 1, y: 1)
            Rectangle()
                .fill(.tint)
                .frame(width: 3, height: Self.barHeight - 11)
        }
        .frame(width: 22)
        .offset(x: position - 11)
    }

    /// Time labels along the bottom, spaced so five to eight fit whatever
    /// the window is.
    private func ticks(width: CGFloat) -> some View {
        let interval = Self.tickInterval(for: span)
        let first = (window.lowerBound / interval).rounded(.up) * interval
        let times = stride(from: first, through: window.upperBound, by: interval)

        return ForEach(Array(times), id: \.self) { time in
            let position = x(time, width: width)
            VStack(spacing: 2) {
                Rectangle()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 1, height: Self.barHeight)
                Text(PlaybackScrubber.timeLabel(time))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(height: Self.labelHeight)
                    // Labels at the ends would hang off the strip.
                    .offset(x: position < 20 ? 14 : position > width - 20 ? -14 : 0)
            }
            .frame(width: 1)
            .offset(x: position)
        }
    }

    static func tickInterval(for span: TimeInterval) -> TimeInterval {
        let candidates: [TimeInterval] = [1, 2, 5, 10, 15, 30, 60, 120, 300]
        return candidates.first { span / $0 <= 8 } ?? 600
    }

    // MARK: - Geometry

    private func x(_ time: TimeInterval, width: CGFloat) -> CGFloat {
        guard span > 0 else { return 0 }
        return CGFloat((time - windowStart) / span) * width
    }

    private func time(atX x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return windowStart }
        return windowStart + TimeInterval(x / width) * span
    }

    /// Puts the selection in the middle of the window, or as near as the
    /// track's edges allow.
    private func recentre() {
        let centre = end.map { (start + $0) / 2 } ?? start
        windowStart = clampWindowStart(centre - span / 2)
    }

    private func clampWindowStart(_ value: TimeInterval) -> TimeInterval {
        max(0, min(value, duration - span))
    }

    // MARK: - Dragging

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag == nil {
                    drag = pick(atX: value.startLocation.x, width: width)
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    #endif
                }
                let time = time(atX: value.location.x, width: width)
                switch drag {
                case .start:
                    let ceiling = end.map { $0 - SongMarker.minimumClipLength } ?? duration
                    start = max(0, min(time, ceiling))
                case .end:
                    end = max(start + SongMarker.minimumClipLength, min(time, duration))
                case .pan(let origin):
                    let shift = TimeInterval(value.translation.width / width) * span
                    windowStart = clampWindowStart(origin - shift)
                case .nothing, nil:
                    break
                }
            }
            .onEnded { _ in drag = nil }
    }

    /// Which thing a touch at `x` takes hold of: the nearest handle if one is
    /// within reach, otherwise the window itself.
    private func pick(atX touch: CGFloat, width: CGFloat) -> Drag {
        var nearest: (Drag, CGFloat) = (.start, abs(x(start, width: width) - touch))
        if let end {
            let distance = abs(x(end, width: width) - touch)
            if distance < nearest.1 { nearest = (.end, distance) }
        }
        if nearest.1 <= Self.grabRadius { return nearest.0 }
        return zoom == .whole ? .nothing : .pan(from: windowStart)
    }
}

#Preview("Clip") {
    @Previewable @State var start: TimeInterval = 71
    @Previewable @State var end: TimeInterval? = 84.5
    MarkerRangeEditor(start: $start, end: $end, duration: 245, playhead: 75)
        .tint(.pink)
        .padding()
}

#Preview("Point") {
    @Previewable @State var start: TimeInterval = 71
    @Previewable @State var end: TimeInterval? = nil
    MarkerRangeEditor(start: $start, end: $end, duration: 245, playhead: 0)
        .padding()
}
