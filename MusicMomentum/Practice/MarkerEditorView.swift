//
//  MarkerEditorView.swift
//  MusicMomentum
//

import SwiftData
import SwiftUI

/// The sheet for placing or adjusting a marker. Nothing is written until
/// Save, and the view never touches the store: it reports what the user
/// settled on and the caller decides where it goes.
struct MarkerEditorView: View {
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

    /// How far before the end handle the End cue drops the playhead.
    private static let leadIn: TimeInterval = 2
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

    /// Writes are dropped once the marker is a point again: a field being
    /// torn off screen mustn't bring the end back.
    private var endBinding: Binding<TimeInterval> {
        Binding(get: { end ?? start }, set: { if end != nil { end = $0 } })
    }

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

    /// Drawn as the pills themselves, since that's what the choice looks like.
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

    /// The cue buttons leave the song running: a snippet that stops itself
    /// can't tell you whether the clip is the right piece of music.
    private var transportRow: some View {
        HStack(spacing: 8) {
            playPauseButton

            if let end {
                cueButton("Start", spoken: "Play from the start of the clip") {
                    controller.playFrom(start)
                }
                // Before the end, so you hear the clip run into it.
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

/// Only writes back a time it could parse, and only once editing ends.
private struct PreciseTimeField: View {
    @Binding var time: TimeInterval
    let range: ClosedRange<TimeInterval>
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
