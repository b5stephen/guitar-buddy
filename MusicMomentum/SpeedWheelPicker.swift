//
//  SpeedWheelPicker.swift
//  MusicMomentum
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A rotary wheel for practice speed, one haptic detent per percent. The
/// wheel itself never clamps — it keeps turning under the finger at either
/// limit — only the value and the arc around the rim do.
struct SpeedWheelPicker: View {
    @Binding var speed: Double

    var diameter: CGFloat = 260

    /// Integers so tick generation and snapping never drift on float arithmetic.
    private let minPercent = 30
    private let maxPercent = 100

    private let degreesPerPercent: Double = 4

    /// Unbounded, unlike the value.
    @State private var wheelAngle: Double = 0
    /// Live, unrounded value during a drag. Clamped on every update so
    /// reversing out of a limit responds immediately.
    @State private var dragPercent: Double?
    /// `nil` while the finger is inside the hub, where the angle is unstable.
    @State private var lastTouchAngle: Double?

    #if canImport(UIKit)
    private let tick = UIImpactFeedbackGenerator(style: .rigid)
    private let limit = UIImpactFeedbackGenerator(style: .medium)
    #endif

    var body: some View {
        VStack(spacing: 16) {
            wheel
                .frame(width: diameter, height: diameter)
                .contentShape(.circle)
                .gesture(rotationGesture)
                // The drag gesture has `minimumDistance: 0`, so a plain
                // `.onTapGesture` never fires. The drag a double tap also
                // triggers moves no distance and commits the value unchanged.
                .simultaneousGesture(TapGesture(count: 2).onEnded { reset() })

            Text("Turn the wheel to adjust — double-tap for 100%")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback speed")
        .accessibilityValue("\(displayPercent) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: commit(Double(displayPercent + 1))
            case .decrement: commit(Double(displayPercent - 1))
            @unknown default: break
            }
        }
    }

    // MARK: - Wheel

    private var wheel: some View {
        ZStack {
            rim
            gauge
            teeth
                .rotationEffect(.degrees(wheelAngle))
            hub
        }
    }

    private var rim: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(.tertiarySystemFill), Color(.quaternarySystemFill)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .clear, .black.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
    }

    private var gauge: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2 - inset

            context.stroke(
                arc(center: center, radius: radius, to: Double(maxPercent)),
                with: .color(.primary.opacity(0.12)),
                style: StrokeStyle(lineWidth: 6, lineCap: .round)
            )
            context.stroke(
                arc(center: center, radius: radius, to: ringPercent),
                with: .style(.tint),
                style: StrokeStyle(lineWidth: 6, lineCap: .round)
            )
        }
        .animation(isDragging ? nil : .snappy(duration: 0.35), value: ringPercent)
    }

    private var teeth: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = size.width / 2 - inset - 16
            let count = Int(360 / degreesPerPercent)

            for index in 0..<count {
                let isMajor = index % 5 == 0
                let angle = Angle.degrees(Double(index) * degreesPerPercent)
                var path = Path()
                path.move(to: point(from: center, radius: outer, angle: angle))
                path.addLine(to: point(from: center, radius: outer - (isMajor ? 14 : 8), angle: angle))
                context.stroke(
                    path,
                    with: .color(.primary.opacity(isMajor ? 0.35 : 0.18)),
                    style: StrokeStyle(lineWidth: isMajor ? 2 : 1.5, lineCap: .round)
                )
            }
        }
    }

    private var hub: some View {
        ZStack {
            Circle()
                .fill(.background)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))

            VStack(spacing: 2) {
                Text("SPEED")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .kerning(1.6)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(displayPercent)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .animation(.snappy(duration: 0.15), value: displayPercent)
            }
        }
        .frame(width: diameter * 0.58, height: diameter * 0.58)
        .allowsHitTesting(false)
    }

    // MARK: - Gesture

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let centre = CGPoint(x: diameter / 2, y: diameter / 2)
                let dx = value.location.x - centre.x
                let dy = value.location.y - centre.y

                guard hypot(dx, dy) > diameter * 0.22 else {
                    lastTouchAngle = nil
                    return
                }

                // Screen y grows downwards, so atan2 grows clockwise.
                let angle = atan2(dy, dx) * 180 / .pi

                guard let previous = lastTouchAngle else {
                    lastTouchAngle = angle
                    if dragPercent == nil { dragPercent = Double(currentPercent) }
                    #if canImport(UIKit)
                    tick.prepare()
                    limit.prepare()
                    #endif
                    return
                }

                lastTouchAngle = angle
                let delta = shortestDelta(from: previous, to: angle)
                wheelAngle += delta
                update(by: delta / degreesPerPercent)
            }
            .onEnded { _ in
                lastTouchAngle = nil
                if let dragPercent { commit(dragPercent) }
                dragPercent = nil
            }
    }

    /// Wrapped into ±180 so crossing the 3 o'clock seam isn't a full turn back.
    private func shortestDelta(from previous: Double, to current: Double) -> Double {
        var delta = current - previous
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return delta
    }

    // MARK: - Values

    private var isDragging: Bool { dragPercent != nil }

    private var currentPercent: Int { clamp(Int((speed * 100).rounded())) }

    private var displayPercent: Int {
        dragPercent.map { clamp(Int($0.rounded())) } ?? currentPercent
    }

    /// Unrounded, so the arc grows smoothly rather than stepping.
    private var ringPercent: Double { dragPercent ?? Double(currentPercent) }

    private var inset: CGFloat { 12 }

    /// Screen angles run 0° at 3 o'clock, clockwise, so the gap is centred on 90°.
    private var sweep: Double { 284 }
    private var startAngle: Double { 90 + (360 - sweep) / 2 }

    private func arc(center: CGPoint, radius: CGFloat, to percent: Double) -> Path {
        var path = Path()
        let travelled = (percent - Double(minPercent)) / Double(maxPercent - minPercent) * sweep
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(startAngle + travelled),
            clockwise: false
        )
        return path
    }

    private func point(from centre: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(
            x: centre.x + radius * cos(angle.radians),
            y: centre.y + radius * sin(angle.radians)
        )
    }

    private func clamp(_ percent: Int) -> Int {
        min(max(percent, minPercent), maxPercent)
    }

    /// Clicks once per whole percent crossed and once, harder, on reaching a
    /// limit; past that the wheel turns in silence.
    private func update(by amount: Double) {
        let previous = dragPercent ?? Double(currentPercent)
        let clamped = min(max(previous + amount, Double(minPercent)), Double(maxPercent))
        let before = displayPercent
        dragPercent = clamped

        #if canImport(UIKit)
        if isAtLimit(clamped), !isAtLimit(previous) {
            limit.impactOccurred()
        } else if displayPercent != before {
            tick.impactOccurred(intensity: 0.45)
        }
        #endif

        if displayPercent != before { speed = Double(displayPercent) / 100 }
    }

    private func isAtLimit(_ percent: Double) -> Bool {
        percent <= Double(minPercent) || percent >= Double(maxPercent)
    }

    private func commit(_ raw: Double) {
        let snapped = clamp(Int(raw.rounded()))
        guard snapped != currentPercent else { return }
        #if canImport(UIKit)
        tick.impactOccurred(intensity: 0.45)
        #endif
        speed = Double(snapped) / 100
    }

    private func reset() {
        guard currentPercent != maxPercent else { return }
        dragPercent = nil
        #if canImport(UIKit)
        limit.impactOccurred()
        #endif
        speed = 1.0
    }
}

#Preview {
    @Previewable @State var speed = 0.75
    SpeedWheelPicker(speed: $speed)
        .padding()
        .tint(.pink)
}
