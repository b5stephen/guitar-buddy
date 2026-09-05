//
//  SpeedWheelPicker.swift
//  GuitarBuddy
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A circular scroll wheel for dialling in practice speed — drag anywhere on
/// the wheel and it turns under your finger, one detent per percent, with a
/// haptic click on every one. The current value sits in the middle.
///
/// The wheel itself is unbounded: it keeps spinning as long as you keep
/// turning. What stops is the value, and the arc around the rim is what shows
/// it stopping — it fills as the speed climbs and simply holds at either end
/// while the wheel carries on under your finger.
struct SpeedWheelPicker: View {
    @Binding var speed: Double

    /// Overall size of the wheel. The rim, ticks and type all scale from it.
    var diameter: CGFloat = 260

    /// Percent bounds, kept as integers so tick generation and snapping never
    /// drift on floating-point arithmetic.
    private let minPercent = 30
    private let maxPercent = 100

    /// How far the wheel turns for one percent — one detent per tick, 90 ticks
    /// to a full revolution. Dense enough to feel geared, coarse enough that a
    /// fingertip can still land on a single one.
    private let degreesPerPercent: Double = 4

    /// Where the wheel is pointing, in degrees. Free-running and unbounded:
    /// unlike the value, it never clamps, so the wheel always follows the
    /// finger even once the speed has stopped moving.
    @State private var wheelAngle: Double = 0
    /// Live, unrounded value while a drag is in flight. Clamped on every
    /// update, so reversing out of a limit responds immediately rather than
    /// waiting for an overshoot to unwind.
    @State private var dragPercent: Double?
    /// Touch angle at the last gesture update, in degrees. `nil` whenever the
    /// finger is inside the hub, where the angle is too unstable to track.
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
                .onTapGesture(count: 2) { reset() }

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

    /// The dished face the wheel sits in.
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

    /// The fixed arc around the rim: the whole travel of the speed, drawn once
    /// as an unfilled track and again as the distance covered so far. This is
    /// the only thing that stops at the limits, so it's what tells you the
    /// wheel has run out of value to give.
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
                with: .color(.accentColor),
                style: StrokeStyle(lineWidth: 6, lineCap: .round)
            )
        }
        .animation(isDragging ? nil : .snappy(duration: 0.35), value: ringPercent)
    }

    /// The turning part: one tooth per percent, every fifth one longer. They're
    /// evenly spaced the whole way round, so the wheel reads the same however
    /// far it has been spun.
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

    /// The raised centre disc carrying the readout.
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

                // Inside the hub the angle swings wildly for tiny movements,
                // so drop the reference and wait for the finger to come out.
                guard hypot(dx, dy) > diameter * 0.22 else {
                    lastTouchAngle = nil
                    return
                }

                // Screen y grows downwards, so atan2 grows clockwise — which
                // is the direction that should raise the speed.
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

    /// Signed degrees from `previous` to `current`, wrapped into ±180 so a drag
    /// across the 3 o'clock seam doesn't read as a full turn backwards.
    private func shortestDelta(from previous: Double, to current: Double) -> Double {
        var delta = current - previous
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return delta
    }

    // MARK: - Values

    private var isDragging: Bool { dragPercent != nil }

    private var currentPercent: Int { clamp(Int((speed * 100).rounded())) }

    /// Rounded value on show in the hub.
    private var displayPercent: Int {
        dragPercent.map { clamp(Int($0.rounded())) } ?? currentPercent
    }

    /// Unrounded value the gauge is drawn at, so the arc grows smoothly rather
    /// than stepping tick to tick.
    private var ringPercent: Double { dragPercent ?? Double(currentPercent) }

    /// Distance from the view's edge to the centre of the gauge track.
    private var inset: CGFloat { 12 }

    /// Total sweep of the gauge, and where it starts. Screen angles run 0° at
    /// 3 o'clock and grow clockwise, so 90° is straight down: the unused arc is
    /// centred there, splitting the gap evenly at the bottom of the face.
    private var sweep: Double { 284 }
    private var startAngle: Double { 90 + (360 - sweep) / 2 }

    /// The gauge arc from the low end of the range up to `percent`.
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

    /// Advances the live value by a fraction of a percent, clicking once per
    /// whole percent crossed and once, harder, on arrival at either end. Past
    /// that the wheel keeps turning in silence — a knob against its stop has
    /// nothing left to say, and the quiet is the clearest way to say it.
    private func update(by amount: Double) {
        let previous = dragPercent ?? Double(currentPercent)
        let clamped = min(max(previous + amount, Double(minPercent)), Double(maxPercent))
        let before = displayPercent
        dragPercent = clamped

        #if canImport(UIKit)
        if isAtLimit(clamped), !isAtLimit(previous) {
            limit.impactOccurred()
        } else if displayPercent != before {
            // Haptics only fire on a real device — the simulator stays silent.
            tick.impactOccurred(intensity: 0.45)
        }
        #endif

        if displayPercent != before { speed = Double(displayPercent) / 100 }
    }

    private func isAtLimit(_ percent: Double) -> Bool {
        percent <= Double(minPercent) || percent >= Double(maxPercent)
    }

    /// Writes a final, snapped value back to the binding.
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
}
