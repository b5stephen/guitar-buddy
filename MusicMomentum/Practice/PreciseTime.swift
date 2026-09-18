//
//  PreciseTime.swift
//  MusicMomentum
//

import Foundation

/// Tenth-of-a-second time strings, for placing a point on a beat.
nonisolated enum PreciseTime {
    /// `1:03.4`; hours only when the track needs them.
    static func format(_ seconds: TimeInterval) -> String {
        let tenths = Int((seconds * 10).rounded())
        let (h, m, s, t) = (tenths / 36000, (tenths % 36000) / 600, (tenths % 600) / 10, tenths % 10)
        return h > 0
            ? String(format: "%d:%02d:%02d.%d", h, m, s, t)
            : String(format: "%d:%02d.%d", m, s, t)
    }

    /// Accepts `m:ss.t`, `m:ss`, `h:mm:ss.t` or bare seconds. `nil` for
    /// anything else.
    static func parse(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        guard let seconds = Double(parts.last!), seconds >= 0 else { return nil }
        var total = seconds
        var scale: Double = 60
        for part in parts.dropLast().reversed() {
            guard let value = Int(part), value >= 0 else { return nil }
            total += Double(value) * scale
            scale *= 60
        }
        return total
    }

    static func nudgeLabel(_ amount: TimeInterval) -> String {
        amount == amount.rounded() ? "\(Int(amount))s" : "\(amount)s"
    }
}
