//
//  ContentView.swift
//  MusicMomentum
//

import MusicKit
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    /// Owned by `RootTabView`, since the saved list drives it too. `@Bindable`
    /// rather than `let` so the speed wheel can still bind to `playbackRate`.
    @Bindable var controller: PlaybackController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query private var savedSongs: [SavedSong]
    @State private var showPicker = false
    @State private var markerSheet: MarkerSheet?

    /// What the marker sheet is open for. `Identifiable` so `.sheet(item:)`
    /// can drive it; editing gets the marker's own identity so switching
    /// straight from one marker to another rebuilds the sheet.
    private enum MarkerSheet: Identifiable {
        case new(start: TimeInterval)
        case edit(SongMarker)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let marker): "edit-\(marker.persistentModelID.hashValue)"
            }
        }
    }

    var body: some View {
        // Everything below the wheel is on fixed spacing and everything above
        // it is one block, so the two gaps either side of the wheel are the
        // only ones that stretch — spare height goes there, and the screen
        // only starts scrolling once they've given back all they have.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if controller.selectedSong != nil {
                        loadedSong(width: proxy.size.width)
                    } else if controller.canUseMusic {
                        noSong(width: proxy.size.width)
                    } else {
                        noAccess(width: proxy.size.width)
                    }

                    messages
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .sheet(isPresented: $showPicker) {
            SongPickerView { song in
                Task { await controller.select(song: song) }
            }
        }
        .sheet(item: $markerSheet) { sheet in
            if let duration = controller.duration {
                switch sheet {
                case .new(let start):
                    MarkerEditorView(
                        initialStart: start,
                        duration: duration,
                        controller: controller,
                        onSave: addMarker
                    )
                case .edit(let marker):
                    MarkerEditorView(
                        marker: marker,
                        duration: duration,
                        controller: controller,
                        onSave: { name, start, end in update(marker, name: name, start: start, end: end) },
                        onDelete: { delete(marker) }
                    )
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The ticker was idle while we were backgrounded, so the playhead
            // needs one read to catch up.
            if phase == .active { controller.refreshPlaybackTime() }
        }
    }

    // MARK: - Practising

    @ViewBuilder
    private func loadedSong(width: CGFloat) -> some View {
        nowPlaying

        Spacer(minLength: 16)

        SpeedWheelPicker(speed: $controller.playbackRate, diameter: wheelDiameter(width: width))

        Spacer(minLength: 16)

        timeline
            .padding(.bottom, 34)

        transportControls

        if let caption = loopCaption {
            Text(caption)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.tint)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .padding(.horizontal, 24)
        }
    }

    /// The wheel is drawn from one number, so it can simply be told a smaller
    /// one on a narrow phone rather than being clipped by it.
    private func wheelDiameter(width: CGFloat) -> CGFloat {
        min(260, max(160, width - 130))
    }

    /// The bar and, under it, the pills that name what the bar is drawing.
    /// The two halves of one idea: where the markers fall, and which ones
    /// they are.
    @ViewBuilder
    private var timeline: some View {
        VStack(spacing: 10) {
            PlaybackScrubber(
                position: controller.playbackTime,
                duration: controller.duration,
                markers: scrubberMarkers,
                onScrub: { _ in controller.isScrubbing = true },
                onCommit: { controller.endScrub(at: $0) }
            )
            // Wider than the usual 16pt: the bar spans the full width, so it
            // needs more breathing room off the edges than the centred
            // content above it.
            .padding(.horizontal, 32)

            if let saved = savedSong, !saved.markers.isEmpty {
                MarkerPills(
                    markers: saved.sortedMarkers,
                    isLooping: { controller.isLooping($0) },
                    isCued: { isCued($0) },
                    onTap: { tapped($0) },
                    onPlayLoop: { controller.playOnLoop($0) },
                    onJump: { controller.jump(to: $0) },
                    onEdit: { markerSheet = .edit($0) },
                    onDelete: { delete($0) }
                )
            }
        }
    }

    /// Loop, skip back, play/pause, skip forward, mark — the moves you make
    /// over and over when drilling a passage, all on one row within reach of
    /// one thumb. The two round buttons bookend it: what the loop is doing at
    /// one end, and how to add to what it can loop at the other.
    ///
    /// Five controls, not six: an odd number is what puts play/pause dead
    /// centre, and restart was the one that earned its place least — dragging
    /// the playhead to the start does the same job, and a loop already
    /// restarts itself.
    private var transportControls: some View {
        HStack(spacing: 0) {
            loopButton
                .frame(maxWidth: .infinity)

            transportButton("gobackward.10", label: "Back 10 seconds") {
                controller.skip(by: -10)
            }
            .frame(maxWidth: .infinity)

            Button {
                controller.togglePlayPause()
            } label: {
                Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")
            .frame(maxWidth: .infinity)

            transportButton("goforward.10", label: "Forward 10 seconds") {
                controller.skip(by: 10)
            }
            .frame(maxWidth: .infinity)

            markButton
                .frame(maxWidth: .infinity)
        }
        // Five equal shares rather than a fixed gap: it keeps play/pause on
        // the screen's centre line whatever the width, and the ends stay on
        // a 390pt phone instead of being pushed off it.
        .frame(maxWidth: 430)
        .padding(.horizontal, 12)
    }

    /// Turns looping on and off — the only control that does. With the button
    /// on and nothing lit it's the whole track, which is what you want when
    /// you're learning a song rather than drilling a passage.
    private var loopButton: some View {
        Button {
            controller.toggleLoop()
        } label: {
            Image(systemName: "repeat")
                .font(.system(size: 19, weight: .semibold))
                .symbolEffect(.pulse, isActive: controller.isLoopOn)
                .frame(width: 46, height: 46)
                .background(
                    controller.isLoopOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    in: Circle()
                )
                .foregroundStyle(controller.isLoopOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Loop")
        .accessibilityValue(loopDescription)
        .accessibilityAddTraits(controller.isLoopOn ? .isSelected : [])
    }

    /// Mirrors the loop button at the other end of the row.
    private var markButton: some View {
        Button {
            markerSheet = .new(start: controller.pauseForMarking())
        } label: {
            MarkGlyph()
                .frame(width: 22, height: 22)
                .frame(width: 46, height: 46)
                .background(.quaternary, in: Circle())
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(controller.duration == nil)
        .accessibilityLabel("Mark this point")
    }

    /// What the loop is doing, said out loud under the transport. The pills
    /// and the lit bands show the scope, but only in a row you may have
    /// scrolled past — this is the one line that's always there.
    private var loopCaption: String? {
        guard let loop = controller.loop else { return nil }
        let segments = loop.segments
        switch segments.count {
        case 0:
            return "Looping whole song"
        case 1:
            guard let name = marker(for: segments[0].markerID)?.name else { return "Looping one clip" }
            return "Looping \(name)"
        default:
            let total = segments.reduce(0) { $0 + ($1.end - $1.start) }
            return "Looping \(segments.count) clips · \(PlaybackScrubber.lengthLabel(total))"
        }
    }

    /// What the loop button is currently looping, for VoiceOver — the caption
    /// below carries this visually, but it's a separate element to the button.
    private var loopDescription: String {
        guard let loop = controller.loop else { return "Off" }
        let clips = loop.segments.count
        switch clips {
        case 0: return "Whole song"
        case 1: return "One clip"
        default: return "\(clips) clips"
        }
    }

    // MARK: - Markers

    /// A pill or tag tap. With the loop off it's navigation, points and clips
    /// alike. With it on, a clip goes in or out of the loop's scope instead —
    /// the context menu's Jump to Start is there when you want to move without
    /// reshaping a running loop.
    private func tapped(_ marker: SongMarker) {
        if controller.isLoopOn, marker.isClip {
            controller.toggleLoop(for: marker)
        } else {
            controller.jump(to: marker)
        }
    }

    /// The playhead is inside this clip with the loop off: the clip the loop
    /// button would pick up if you reached for it.
    private func isCued(_ marker: SongMarker) -> Bool {
        guard !controller.isLoopOn, let end = marker.endTime else { return false }
        return controller.playbackTime >= marker.startTime && controller.playbackTime < end
    }

    private func marker(for id: AnyHashable) -> SongMarker? {
        savedSong?.markers.first { $0.persistentModelID == id as? PersistentIdentifier }
    }

    /// The same markers, as the footprints the scrubber draws.
    private var scrubberMarkers: [PlaybackScrubber.Marker] {
        (savedSong?.sortedMarkers ?? []).map {
            .init(
                id: $0.persistentModelID,
                start: $0.startTime,
                end: $0.endTime,
                isLooping: controller.isLooping($0)
            )
        }
    }

    /// Marking a song puts it on the saved list if it isn't there yet —
    /// markers live on the saved entry, and a mark you couldn't get back to
    /// would be no use.
    private func addMarker(name: String, start: TimeInterval, end: TimeInterval?) {
        guard let song = savedSong ?? controller.saveCurrentSong() else { return }
        SongMarker.add(to: song, name: name, startTime: start, endTime: end, in: modelContext)
    }

    private func update(_ marker: SongMarker, name: String, start: TimeInterval, end: TimeInterval?) {
        marker.set(name: name, start: start, end: end)
        try? modelContext.save()
        controller.markerChanged(marker)
    }

    private func delete(_ marker: SongMarker) {
        controller.markerDeleted(marker)
        SongMarker.delete(marker, in: modelContext)
    }

    private func transportButton(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 26))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Header

    private var nowPlaying: some View {
        VStack(spacing: 4) {
            Text(controller.selectedSong?.title ?? "")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(controller.selectedSong?.artistName ?? "")
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                saveChip
                changeSongChip
            }
            .padding(.top, 8)
        }
        .padding(.horizontal)
    }

    /// Puts the current speed on the practice list. Deliberately not a toolbar
    /// item: this screen has no `NavigationStack`, and its layout is tuned to
    /// fit one screen. The label names the speed so the button says what it
    /// will do without needing a confirmation step.
    @ViewBuilder
    private var saveChip: some View {
        let percent = Int((controller.playbackRate * 100).rounded())
        let saved = savedSong
        let isCurrent = saved?.percent == percent

        Button {
            controller.saveCurrentSong()
        } label: {
            if isCurrent {
                chipLabel("Saved at \(percent)%", systemImage: "bookmark.fill", isPrompting: false)
            } else if saved != nil {
                chipLabel("Update to \(percent)%", systemImage: "bookmark.fill", isPrompting: true)
            } else {
                chipLabel("Save at \(percent)%", systemImage: "bookmark", isPrompting: true)
            }
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
    }

    /// Choosing a song is the first thing you do and then never again this
    /// session, so once there's a song on screen it steps back to a chip
    /// beside the save one rather than holding the prominent button.
    private var changeSongChip: some View {
        Button {
            Task { showPicker = await controller.requestAuthorizationIfNeeded() }
        } label: {
            chipLabel("Change song", systemImage: "arrow.left.arrow.right", isPrompting: false)
        }
        .buttonStyle(.plain)
        .disabled(!controller.canUseMusic)
    }

    /// The one chip shape both header buttons are cut from — a prompting chip
    /// is the one there's a reason to tap right now.
    private func chipLabel(_ title: String, systemImage: String, isPrompting: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isPrompting ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
            .foregroundStyle(isPrompting ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }

    /// The saved entry for the song on screen, if it's on the list. Reads the
    /// `@Query` results rather than fetching, so the button restyles itself the
    /// moment the store changes — including from the Saved tab.
    private var savedSong: SavedSong? {
        guard let songID = controller.selectedSong?.id.rawValue else { return nil }
        return savedSongs.first { $0.songID == songID }
    }

    // MARK: - Arriving

    /// No song yet.
    @ViewBuilder
    private func noSong(width: CGFloat) -> some View {
        ArrivalState(
            diameter: wheelDiameter(width: width),
            systemImage: "music.note.list",
            headline: "Nothing loaded yet",
            detail: "Pick a song from Apple Music and slow it down to a speed you can actually play.",
            actionTitle: "Choose a Song",
            footnote: "Or open Saved to pick up where you left off."
        ) {
            // Asking here, rather than at launch, means the system prompt
            // lands on the tap that needs it.
            Task { showPicker = await controller.requestAuthorizationIfNeeded() }
        }
    }

    /// The same screen, locked. Settings is the only place the decision can
    /// actually be changed now, so the button goes there rather than asking
    /// again for something the system will no longer prompt for.
    @ViewBuilder
    private func noAccess(width: CGFloat) -> some View {
        ArrivalState(
            diameter: wheelDiameter(width: width),
            systemImage: "lock",
            headline: "Apple Music access needed",
            detail: "Music Momentum plays songs from your own library and Apple Music. It can't reach either one until you allow it.",
            actionTitle: "Open Settings",
            footnote: "Settings › Music Momentum › Media & Apple Music"
        ) {
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            #endif
        }
    }

    // MARK: - Messages

    @ViewBuilder
    private var messages: some View {
        VStack(spacing: 8) {
            if let warning = controller.rateWarning {
                banner(warning, systemImage: "exclamationmark.triangle.fill", colour: .orange, opacity: 0.14)
            }
            if let error = controller.errorMessage {
                banner(error, systemImage: "exclamationmark.circle.fill", colour: .red, opacity: 0.12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, controller.rateWarning == nil && controller.errorMessage == nil ? 0 : 16)
    }

    /// Bad news gets a shape of its own. Loose coloured text under a screen
    /// this dense reads as part of the layout; a tinted block reads as
    /// something that happened.
    private func banner(
        _ text: String,
        systemImage: String,
        colour: Color,
        opacity: Double
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
        .foregroundStyle(colour)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(colour.opacity(opacity), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

/// A practice screen with no song in it. Built from the same bones as the
/// loaded one — the same flexible gaps, the dial's own silhouette where the
/// dial goes — so arriving at a song reads as this screen filling in rather
/// than a different screen replacing it.
private struct ArrivalState: View {
    var diameter: CGFloat
    var systemImage: String
    var headline: String
    var detail: String
    var actionTitle: String
    var footnote: String
    var action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            DialSilhouette(diameter: diameter, systemImage: systemImage)

            Spacer(minLength: 16)

            VStack(spacing: 8) {
                Text(headline)
                    .font(.title2.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)

            Button(action: action) {
                Text(actionTitle)
                    .frame(height: 50)
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.top, 24)

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 40)
        }
        // Takes the whole height it's given, so its two gaps — not the stack
        // around it — are what absorb the spare space, exactly as on the
        // loaded screen.
        .frame(maxHeight: .infinity)
    }
}

/// The speed wheel with nothing to say: its rim and its teeth, no value arc,
/// and a glyph where the number would be. It holds the practice screen's
/// centre of gravity while there's nothing loaded, so the layout doesn't
/// lurch when a song arrives.
struct DialSilhouette: View {
    var diameter: CGFloat
    var systemImage: String

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.quaternary, lineWidth: 6)
                .padding(9)

            Canvas { context, size in
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let outer = size.width / 2 - 28
                for index in 0..<90 {
                    let isMajor = index % 5 == 0
                    let angle = Angle.degrees(Double(index) * 4)
                    var path = Path()
                    path.move(to: point(from: centre, radius: outer, angle: angle))
                    path.addLine(to: point(from: centre, radius: outer - (isMajor ? 14 : 8), angle: angle))
                    context.stroke(
                        path,
                        with: .color(.primary.opacity(0.12)),
                        style: StrokeStyle(lineWidth: isMajor ? 2 : 1.5, lineCap: .round)
                    )
                }
            }

            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.2, weight: .light))
                .foregroundStyle(.primary.opacity(0.3))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private func point(from centre: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(
            x: centre.x + radius * cos(angle.radians),
            y: centre.y + radius * sin(angle.radians)
        )
    }
}

/// The mark button's glyph: the point marker the track draws, with a plus
/// beside it. No SF Symbol says "put a mark *here*" — flag came closest and
/// read as reporting a problem.
struct MarkGlyph: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 24
            var path = Path()
            path.move(to: CGPoint(x: 3.5 * scale, y: 19.5 * scale))
            path.addLine(to: CGPoint(x: 20.5 * scale, y: 19.5 * scale))
            path.move(to: CGPoint(x: 9 * scale, y: 19.5 * scale))
            path.addLine(to: CGPoint(x: 9 * scale, y: 7.5 * scale))
            path.move(to: CGPoint(x: 15 * scale, y: 5 * scale))
            path.addLine(to: CGPoint(x: 20.5 * scale, y: 5 * scale))
            path.move(to: CGPoint(x: 17.75 * scale, y: 2.25 * scale))
            path.addLine(to: CGPoint(x: 17.75 * scale, y: 7.75 * scale))
            context.stroke(
                path,
                with: .style(.foreground),
                style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round)
            )
        }
    }
}

#Preview {
    ContentView(controller: PlaybackController())
        .modelContainer(try! AppSchema.inMemoryContainer())
}

#Preview("Nothing loaded") {
    ArrivalState(
        diameter: 260,
        systemImage: "music.note.list",
        headline: "Nothing loaded yet",
        detail: "Pick a song from Apple Music and slow it down to a speed you can actually play.",
        actionTitle: "Choose a Song",
        footnote: "Or open Saved to pick up where you left off."
    ) {}
        .padding(.vertical, 16)
        .tint(.pink)
}

#Preview("No access") {
    ArrivalState(
        diameter: 260,
        systemImage: "lock",
        headline: "Apple Music access needed",
        detail: "Music Momentum plays songs from your own library and Apple Music. It can't reach either one until you allow it.",
        actionTitle: "Open Settings",
        footnote: "Settings › Music Momentum › Media & Apple Music"
    ) {}
        .padding(.vertical, 16)
        .tint(.pink)
}

