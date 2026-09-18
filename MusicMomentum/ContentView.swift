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
    @Bindable var controller: PlaybackController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query private var savedSongs: [SavedSong]
    @State private var showPicker = false
    @State private var markerSheet: MarkerSheet?

    /// Editing carries the marker's identity so switching straight from one
    /// marker to another rebuilds the sheet.
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
        // The gaps either side of the wheel absorb spare height; the screen only
        // scrolls once they've given it all back. The bottom gap is capped so it
        // lifts the transport off the tab bar without pulling it up the screen.
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

                    Spacer(minLength: 0)
                        .frame(maxHeight: 40)
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

    private func wheelDiameter(width: CGFloat) -> CGFloat {
        min(260, max(160, width - 130))
    }

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

    /// Five controls, not six: an odd number puts play/pause dead centre.
    /// Restart was dropped — dragging to the start does the same job.
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
        // Equal shares rather than a fixed gap keeps play/pause on the centre
        // line at any width, and the ends on screen on a 390pt phone.
        .frame(maxWidth: 430)
        .padding(.horizontal, 12)
    }

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

    /// For VoiceOver: the caption is a separate element to the button.
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

    /// With the loop off a tap navigates; with it on, a clip tap reshapes the
    /// scope instead (the menu's Jump to Start still navigates).
    private func tapped(_ marker: SongMarker) {
        if controller.isLoopOn, marker.isClip {
            controller.toggleLoop(for: marker)
        } else {
            controller.jump(to: marker)
        }
    }

    /// Playhead inside this clip with the loop off.
    private func isCued(_ marker: SongMarker) -> Bool {
        guard !controller.isLoopOn, let end = marker.endTime else { return false }
        return controller.playbackTime >= marker.startTime && controller.playbackTime < end
    }

    private func marker(for id: AnyHashable) -> SongMarker? {
        savedSong?.markers.first { $0.persistentModelID == id as? PersistentIdentifier }
    }

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

    /// Markers live on the saved entry, so marking an unsaved song saves it.
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

    private var changeSongChip: some View {
        Button {
            Task { showPicker = await controller.requestAuthorizationIfNeeded() }
        } label: {
            chipLabel("Change song", systemImage: "arrow.left.arrow.right", isPrompting: false)
        }
        .buttonStyle(.plain)
        .disabled(!controller.canUseMusic)
    }

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

    /// Reads the `@Query` results rather than fetching, so the chip restyles
    /// the moment the store changes — including from the Saved tab.
    private var savedSong: SavedSong? {
        guard let songID = controller.selectedSong?.id.rawValue else { return nil }
        return savedSongs.first { $0.songID == songID }
    }

    // MARK: - Arriving

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
            Task { showPicker = await controller.requestAuthorizationIfNeeded() }
        }
    }

    /// Once denied the system won't prompt again, so the button goes to Settings.
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

/// The practice screen with no song: same flexible gaps, the dial's silhouette
/// where the dial goes, so a song arriving reads as the screen filling in.
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
        // So its own gaps, not the stack around it, absorb the spare space.
        .frame(maxHeight: .infinity)
    }
}

/// The speed wheel's rim and teeth with a glyph where the number would be.
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

/// The point marker the track draws, with a plus. No SF Symbol says "put a
/// mark here" — flag came closest and read as reporting a problem.
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

