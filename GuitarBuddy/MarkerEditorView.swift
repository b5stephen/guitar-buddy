//
//  MarkerEditorView.swift
//  GuitarBuddy
//

import SwiftUI

/// The sheet for placing or adjusting a marker: a name, a start time, an
/// optional end time, and the zoomable strip for dragging either into place.
///
/// Nothing is written until Save. The view doesn't know about the store at
/// all — it reports what the user settled on and the caller decides where it
/// goes, which keeps the storage rules in one place and this view previewable.
struct MarkerEditorView: View {
    /// The marker being edited, or `nil` when placing a new one.
    let marker: SongMarker?
    let duration: TimeInterval
    let controller: PlaybackController
    let onSave: (_ name: String, _ start: TimeInterval, _ end: TimeInterval?) -> Void
    var onDelete: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var start: TimeInterval
    @State private var end: TimeInterval?
    @State private var confirmingDelete = false

    /// How much of the track an audition plays either side of a handle.
    private static let auditionLength: TimeInterval = 2
    /// The end time a clip starts life with, before the user drags it.
    private static let defaultClipLength: TimeInterval = 4

    init(
        marker: SongMarker? = nil,
        initialStart: TimeInterval = 0,
        duration: TimeInterval,
        controller: PlaybackController,
        onSave: @escaping (_ name: String, _ start: TimeInterval, _ end: TimeInterval?) -> Void,
        onDelete: @escaping () -> Void = {}
    ) {
        self.marker = marker
        self.duration = duration
        self.controller = controller
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: marker?.name ?? "")
        _start = State(initialValue: marker?.startTime ?? initialStart)
        _end = State(initialValue: marker?.endTime)
    }

    private var isEditing: Bool { marker != nil }
    private var canAddEnd: Bool { start + SongMarker.minimumClipLength <= duration }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(end == nil ? "Marker" : "Clip", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Start") {
                    TimeRow(
                        time: $start,
                        range: 0...(end.map { $0 - SongMarker.minimumClipLength } ?? duration),
                        playhead: controller.playbackTime
                    )
                    auditionButton("Play from start", systemImage: "play.fill") {
                        controller.audition(from: start, to: min(start + Self.auditionLength, end ?? duration))
                    }
                }

                Section {
                    if let endBinding = Binding($end) {
                        TimeRow(
                            time: endBinding,
                            range: (start + SongMarker.minimumClipLength)...duration,
                            playhead: controller.playbackTime
                        )
                        auditionButton("Play up to end", systemImage: "play.fill") {
                            controller.audition(from: max(start, endBinding.wrappedValue - Self.auditionLength), to: endBinding.wrappedValue)
                        }
                        auditionButton("Play whole clip", systemImage: "play.circle") {
                            controller.audition(from: start, to: endBinding.wrappedValue)
                        }
                        Button("Clear End Time", role: .destructive) {
                            withAnimation { end = nil }
                        }
                    } else {
                        Button {
                            withAnimation {
                                end = min(duration, start + Self.defaultClipLength)
                            }
                        } label: {
                            Label("Add End Time", systemImage: "plus")
                        }
                        .disabled(!canAddEnd)
                    }
                } header: {
                    Text("End")
                } footer: {
                    Text(end == nil
                        ? "Add an end time to turn this point into a clip you can loop."
                        : "Drag the handles below, or nudge the times above.")
                }

                Section {
                    MarkerRangeEditor(
                        start: $start,
                        end: $end,
                        duration: duration,
                        playhead: controller.playbackTime
                    )
                    .padding(.vertical, 8)
                }

                if isEditing {
                    Section {
                        Button("Delete Marker", role: .destructive) {
                            confirmingDelete = true
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Marker" : "New Marker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, start, end)
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Delete this marker?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
    }

    private func auditionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

// MARK: - Time row

/// One time: a typed field, a "use the playhead" button, and nudge buttons
/// for the last bit of fine-tuning.
private struct TimeRow: View {
    @Binding var time: TimeInterval
    let range: ClosedRange<TimeInterval>
    let playhead: TimeInterval

    var body: some View {
        HStack {
            PreciseTimeField(time: $time, range: range)
            Spacer()
            Button("Now") { set(playhead) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Set to current position")
        }

        HStack(spacing: 8) {
            nudge(-1)
            nudge(-0.1)
            Spacer()
            nudge(0.1)
            nudge(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.footnote.monospacedDigit())
    }

    private func nudge(_ amount: TimeInterval) -> some View {
        Button {
            set(time + amount)
        } label: {
            Text(amount > 0 ? "+\(PreciseTime.nudgeLabel(amount))" : "−\(PreciseTime.nudgeLabel(-amount))")
                .frame(minWidth: 44)
        }
        .accessibilityLabel(amount > 0 ? "Later by \(PreciseTime.nudgeLabel(amount))" : "Earlier by \(PreciseTime.nudgeLabel(-amount))")
    }

    private func set(_ value: TimeInterval) {
        time = max(range.lowerBound, min(value, range.upperBound))
    }
}

/// A text field showing `m:ss.t` that only writes back a time it could parse,
/// and only once the user has finished typing.
private struct PreciseTimeField: View {
    @Binding var time: TimeInterval
    let range: ClosedRange<TimeInterval>

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0:00.0", text: $text)
            .font(.title2.monospacedDigit())
            .keyboardType(.numbersAndPunctuation)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { if !focused { commit() } }
            .onChange(of: time, initial: true) { if !focused { text = PreciseTime.format(time) } }
            .accessibilityLabel("Time")
            .accessibilityValue(PreciseTime.format(time))
    }

    private func commit() {
        if let parsed = PreciseTime.parse(text) {
            time = max(range.lowerBound, min(parsed, range.upperBound))
        }
        text = PreciseTime.format(time)
    }
}

/// Tenth-of-a-second time strings for the editor. The scrubber's `m:ss` is
/// right for a playhead but not for a point you're placing on a beat.
enum PreciseTime {
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

    /// `1s` or `0.1s`, for the nudge buttons.
    static func nudgeLabel(_ amount: TimeInterval) -> String {
        amount == amount.rounded() ? "\(Int(amount))s" : "\(amount)s"
    }
}

// MARK: - Row label

/// A marker's kind, name and times, as both the practice screen and the
/// saved list draw it.
struct MarkerLabel: View {
    let marker: SongMarker

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: marker.isClip ? "waveform" : "mappin")
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(marker.name)
                    .lineLimit(1)
                Text(marker.timeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("New") {
    MarkerEditorView(initialStart: 71, duration: 245, controller: PlaybackController()) { _, _, _ in }
        .tint(.pink)
}
