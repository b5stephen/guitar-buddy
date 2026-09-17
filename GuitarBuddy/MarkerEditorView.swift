//
//  MarkerEditorView.swift
//  GuitarBuddy
//

import SwiftData
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
    /// Which time the nudge row and Now act on.
    @State private var selected: MarkerHandle = .start

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
        _selected = State(initialValue: marker?.endTime == nil ? .start : .end)
    }

    private var isEditing: Bool { marker != nil }
    private var canAddEnd: Bool { start + SongMarker.minimumClipLength <= duration }

    private enum Kind: Hashable {
        case point, clip
    }

    /// Point or clip, as a switch. Going to clip gives the marker a short end
    /// to drag from; going back to point drops it.
    private var kind: Binding<Kind> {
        Binding(
            get: { end == nil ? .point : .clip },
            set: { newKind in
                withAnimation {
                    switch newKind {
                    case .point:
                        end = nil
                        selected = .start
                    case .clip:
                        end = min(duration, start + Self.defaultClipLength)
                        selected = .end
                    }
                }
            }
        )
    }

    /// The time the nudge row and Now act on. The end can't be selected on
    /// a point, so it falls back to the start.
    private var selectedTime: Binding<TimeInterval> {
        switch selected {
        case .end where end != nil:
            Binding(get: { end ?? start }, set: { end = $0 })
        default:
            $start
        }
    }

    private var startRange: ClosedRange<TimeInterval> {
        0...(end.map { $0 - SongMarker.minimumClipLength } ?? duration)
    }

    private var endRange: ClosedRange<TimeInterval> {
        (start + SongMarker.minimumClipLength)...duration
    }

    private var selectedRange: ClosedRange<TimeInterval> {
        selected == .end && end != nil ? endRange : startRange
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        TextField(end == nil ? "Marker" : "Clip", text: $name)
                            .textInputAutocapitalization(.words)
                        Picker("Kind", selection: kind) {
                            Text("Point").tag(Kind.point)
                            Text("Clip").tag(Kind.clip)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                        .disabled(end == nil && !canAddEnd)
                    }
                }

                // The strip first: it's the control that does most of the
                // work, so it shouldn't be the one you scroll to.
                Section {
                    MarkerRangeEditor(
                        start: $start,
                        end: $end,
                        duration: duration,
                        playhead: controller.playbackTime,
                        onGrab: { selected = $0 }
                    )
                    .padding(.vertical, 8)
                }

                Section {
                    times
                    nudgeRow
                } footer: {
                    if end == nil {
                        Text(canAddEnd
                            ? "Switch to Clip to give this an end time you can loop."
                            : "Too close to the end of the song for a clip.")
                    }
                }

                Section {
                    auditionRow
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

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

    /// The start and, for a clip, the end as big numerals side by side. Tap
    /// one to make it the time the nudges act on; tap the number to type.
    private var times: some View {
        HStack(spacing: 0) {
            if let endBinding = Binding($end) {
                timeColumn("Start", time: $start, range: startRange, handle: .start)
                Divider()
                timeColumn("End", time: endBinding, range: endRange, handle: .end)
            } else {
                timeColumn("Time", time: $start, range: startRange, handle: .start)
            }
        }
        .padding(.vertical, 4)
    }

    private func timeColumn(
        _ title: String,
        time: Binding<TimeInterval>,
        range: ClosedRange<TimeInterval>,
        handle: MarkerHandle
    ) -> some View {
        let isSelected = selected == handle || end == nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(handle == .start ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                    .strokeBorder(.tint, lineWidth: 2)
                    .frame(width: 9, height: 9)
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.4)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            PreciseTimeField(time: time, range: range) { selected = handle }
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .contentShape(.rect)
        .onTapGesture { selected = handle }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// One row of fine adjustment for whichever time is selected: a second
    /// and a tenth either way, and Now to snap it to the playhead.
    private var nudgeRow: some View {
        HStack(spacing: 8) {
            nudge(-1)
            nudge(-0.1)
            Button {
                setSelected(controller.playbackTime)
            } label: {
                Label("Now", systemImage: "arrow.up.to.line")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Set to current position")
            nudge(0.1)
            nudge(1)
        }
        .controlSize(.small)
        .padding(.vertical, 4)
    }

    private func nudge(_ amount: TimeInterval) -> some View {
        Button {
            setSelected(selectedTime.wrappedValue + amount)
        } label: {
            Text(amount > 0 ? "+\(PreciseTime.nudgeLabel(amount))" : "−\(PreciseTime.nudgeLabel(-amount))")
                .font(.footnote.monospacedDigit())
                .frame(minWidth: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(amount > 0 ? "Later by \(PreciseTime.nudgeLabel(amount))" : "Earlier by \(PreciseTime.nudgeLabel(-amount))")
    }

    private func setSelected(_ value: TimeInterval) {
        let range = selectedRange
        selectedTime.wrappedValue = max(range.lowerBound, min(value, range.upperBound))
    }

    /// Quick listens: a couple of seconds either side of a handle, or the
    /// whole clip.
    private var auditionRow: some View {
        HStack(spacing: 8) {
            if let end {
                auditionButton("Start", systemImage: "play.fill") {
                    controller.audition(from: start, to: min(start + Self.auditionLength, end))
                }
                auditionButton("Whole clip", systemImage: "play.fill") {
                    controller.audition(from: start, to: end)
                }
                auditionButton("To end", systemImage: "play.fill") {
                    controller.audition(from: max(start, end - Self.auditionLength), to: end)
                }
            } else {
                auditionButton("Play from here", systemImage: "play.fill") {
                    controller.audition(from: start, to: min(start + Self.auditionLength, duration))
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private func auditionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .accessibilityLabel(title == "Play from here" ? title : "Play \(title.lowercased())")
    }
}

// MARK: - Time field

/// A text field showing `m:ss.t` that only writes back a time it could parse,
/// and only once the user has finished typing.
private struct PreciseTimeField: View {
    @Binding var time: TimeInterval
    let range: ClosedRange<TimeInterval>
    /// Called when the field takes focus, so typing into a time selects it.
    var onFocus: () -> Void = {}

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0:00.0", text: $text)
            .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
            .keyboardType(.numbersAndPunctuation)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { focused ? onFocus() : commit() }
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

#Preview("New") {
    MarkerEditorView(initialStart: 71, duration: 245, controller: PlaybackController()) { _, _, _ in }
        .tint(.pink)
}

#Preview("Edit clip") {
    let container = try! AppSchema.inMemoryContainer()
    let song = SavedSong(songID: "1", speed: 0.8, title: "Little Wing", artistName: "Jimi Hendrix")
    container.mainContext.insert(song)
    let marker = SongMarker.add(to: song, name: "Solo", startTime: 96, endTime: 112.4, in: container.mainContext)
    return MarkerEditorView(marker: marker, duration: 245, controller: PlaybackController()) { _, _, _ in }
        .tint(.pink)
        .modelContainer(container)
}
