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

    /// How far before a handle a cue button drops the playhead, so you hear
    /// the run-up to it rather than starting on top of it.
    private static let leadIn: TimeInterval = 2
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

    /// The end as a non-optional binding, for controls that can only deal in
    /// a time. Reading it once the marker is a point again gives the start
    /// rather than trapping, and writing to it then is dropped: a field being
    /// torn off screen mustn't bring the end back.
    private var endBinding: Binding<TimeInterval> {
        Binding(get: { end ?? start }, set: { if end != nil { end = $0 } })
    }

    /// The time the nudge row and Now act on. The end can't be selected on
    /// a point, so it falls back to the start.
    private var selectedTime: Binding<TimeInterval> {
        switch selected {
        case .end where end != nil: endBinding
        default: $start
        }
    }

    private var startRange: ClosedRange<TimeInterval> {
        0...max(0, end.map { $0 - SongMarker.minimumClipLength } ?? duration)
    }

    private var endRange: ClosedRange<TimeInterval> {
        min(start + SongMarker.minimumClipLength, duration)...duration
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
                        kindSwitch
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
                    transportRow
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

    /// Point or clip, drawn as the two pills themselves rather than as a
    /// segmented control: the choice is what the marker will look like in the
    /// row under the scrubber, so it may as well show you.
    private var kindSwitch: some View {
        HStack(spacing: 6) {
            kindButton(.point, title: "Point") {
                Circle().frame(width: 6, height: 6)
            }
            kindButton(.clip, title: "Clip") {
                SpanGlyph()
            }
            .disabled(end == nil && !canAddEnd)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kind")
    }

    private func kindButton(
        _ value: Kind,
        title: String,
        @ViewBuilder glyph: () -> some View
    ) -> some View {
        let isSelected = kind.wrappedValue == value
        return Button {
            kind.wrappedValue = value
        } label: {
            HStack(spacing: 5) {
                glyph()
                    .opacity(isSelected ? 0.8 : 0.55)
                Text(title)
                    .font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The start and, for a clip, the end as big numerals side by side. Tap
    /// one to make it the time the nudges act on; tap the number to type.
    private var times: some View {
        HStack(spacing: 0) {
            if end != nil {
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
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Spacer(minLength: 4)
                if isSelected {
                    nowChip(for: title)
                }
            }
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

    /// Sets the selected time to wherever the song has got to. It sits up
    /// here rather than among the nudges because it belongs to the number it
    /// writes, and because it's the one control that works in time with the
    /// music: audition a passage and tap this on the beat, instead of having
    /// to already know the number.
    private func nowChip(for title: String) -> some View {
        Button {
            setSelected(controller.playbackTime)
        } label: {
            Text("Now")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(.tint.opacity(0.14), in: Capsule())
                .foregroundStyle(.tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set \(title.lowercased()) to the current position")
    }

    /// One row of fine adjustment for whichever time is selected: a second
    /// and a tenth either way, and Now to snap it to the playhead.
    private var nudgeRow: some View {
        HStack(spacing: 8) {
            nudge(-1)
            nudge(-0.1)
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
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(amount > 0 ? "Later by \(PreciseTime.nudgeLabel(amount))" : "Earlier by \(PreciseTime.nudgeLabel(-amount))")
    }

    private func setSelected(_ value: TimeInterval) {
        let range = selectedRange
        selectedTime.wrappedValue = max(range.lowerBound, min(value, range.upperBound))
    }

    /// The transport, so the song can be listened to properly from in here:
    /// play/pause on the left, and beside it the one or two places worth
    /// dropping the playhead while you're placing a handle.
    ///
    /// The cue buttons start the song and leave it running. A two-second
    /// snippet is enough to tell you a handle landed somewhere, but not
    /// whether the clip is the right piece of music — and a snippet that stops
    /// itself leaves you with nothing to press when you want it to stop
    /// sooner.
    private var transportRow: some View {
        HStack(spacing: 8) {
            playPauseButton

            if let end {
                cueButton("Start", spoken: "Play from the start of the clip") {
                    controller.playFrom(start)
                }
                // Before the end rather than at it: what you're listening for
                // is whether the clip ends in the right place, which you can
                // only hear by running into it.
                cueButton("End", spoken: "Play into the end of the clip") {
                    controller.playFrom(max(start, end - Self.leadIn))
                }
            } else {
                cueButton("Play from here", spoken: "Play from the marker") {
                    controller.playFrom(start)
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private var playPauseButton: some View {
        Button {
            controller.togglePlayPause()
        } label: {
            Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                .font(.footnote.weight(.semibold))
                .frame(width: 30)
                .frame(minHeight: 28)
        }
        .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")
    }

    private func cueButton(
        _ title: String,
        spoken: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.turn.down.right")
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .accessibilityLabel(spoken)
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
