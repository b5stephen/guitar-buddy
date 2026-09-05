//
//  SpeedWheelPicker.swift
//  GuitarBuddy
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A horizontal "ruler" wheel, similar in feel to the Camera app's zoom
/// control — drag left/right to dial in a speed, with the current value shown
/// prominently above. Snaps to 5% increments and gives a light haptic tick as
/// each increment passes.
///
/// SwiftUI has no native circular dial, hence the ruler treatment.
struct SpeedWheelPicker: View {
    @Binding var speed: Double

    /// Percent bounds, kept as integers so tick generation and snapping never
    /// drift on floating-point arithmetic.
    private let minPercent = 30
    private let maxPercent = 100
    private let stepPercent = 5

    /// Horizontal spacing between adjacent 5% ticks.
    private let pointsPerStep: CGFloat = 28
    private let tickWidth: CGFloat = 2

    @State private var dragStartPercent: Int?

    #if canImport(UIKit)
    private let feedback = UIImpactFeedbackGenerator(style: .light)
    #endif

    var body: some View {
        VStack(spacing: 12) {
            Text("\(currentPercent)%")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: speed)
                .accessibilityHidden(true)

            GeometryReader { geo in
                ZStack {
                    ticksRow
                        // Centre the tick for the current value under the indicator.
                        .offset(x: totalWidth / 2 - offset(forPercent: currentPercent))
                        .animation(.interactiveSpring, value: currentPercent)

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 40)
                        .clipShape(.capsule)
                }
                .frame(width: geo.size.width, height: 60)
                .clipped()
                .contentShape(Rectangle())
                .gesture(dragGesture)
            }
            .frame(height: 60)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            Text("Drag to adjust — full speed at 100%")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback speed")
        .accessibilityValue("\(currentPercent) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setPercent(currentPercent + stepPercent)
            case .decrement: setPercent(currentPercent - stepPercent)
            @unknown default: break
            }
        }
    }

    // MARK: - Pieces

    private var ticksRow: some View {
        HStack(spacing: pointsPerStep - tickWidth) {
            ForEach(tickPercents, id: \.self) { percent in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(percent == currentPercent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                        .frame(width: tickWidth, height: isMajorTick(percent) ? 24 : 14)
                    if isMajorTick(percent) {
                        Text("\(percent)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: tickWidth)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStartPercent ?? currentPercent
                if dragStartPercent == nil {
                    dragStartPercent = start
                    #if canImport(UIKit)
                    feedback.prepare()
                    #endif
                }
                let deltaSteps = (-value.translation.width / pointsPerStep).rounded()
                setPercent(start + Int(deltaSteps) * stepPercent)
            }
            .onEnded { _ in dragStartPercent = nil }
    }

    // MARK: - Values

    private var currentPercent: Int {
        clamp(Int((speed * 100).rounded()))
    }

    private var tickPercents: [Int] {
        Array(stride(from: minPercent, through: maxPercent, by: stepPercent))
    }

    private var totalWidth: CGFloat {
        CGFloat(tickPercents.count - 1) * pointsPerStep
    }

    private func offset(forPercent percent: Int) -> CGFloat {
        CGFloat(percent - minPercent) / CGFloat(stepPercent) * pointsPerStep
    }

    private func isMajorTick(_ percent: Int) -> Bool {
        percent % 10 == 0
    }

    private func clamp(_ percent: Int) -> Int {
        min(max(percent, minPercent), maxPercent)
    }

    private func setPercent(_ raw: Int) {
        let rounded = Int((Double(raw) / Double(stepPercent)).rounded()) * stepPercent
        let snapped = clamp(rounded)
        guard snapped != currentPercent else { return }
        #if canImport(UIKit)
        // Haptics only fire on a real device — the simulator stays silent.
        feedback.impactOccurred(intensity: 0.5)
        #endif
        speed = Double(snapped) / 100
    }
}

#Preview {
    @Previewable @State var speed = 0.75
    SpeedWheelPicker(speed: $speed)
        .padding()
}
