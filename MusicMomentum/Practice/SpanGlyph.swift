//
//  SpanGlyph.swift
//  MusicMomentum
//

import SwiftUI

/// The clip glyph. No SF Symbol reads as a span at this size without also
/// reading as an arrow.
struct SpanGlyph: View {
    /// Scaled with the label: the glyph is the only thing telling a clip from
    /// a point, so it can't stay 10pt next to accessibility-sized type.
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
