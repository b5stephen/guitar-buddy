//
//  RootTabView.swift
//  GuitarBuddy
//

import SwiftData
import SwiftUI

/// The app's top level: practice on one tab, the songs you've saved on the
/// other. `TabView` keeps both tabs alive, so switching away from practice
/// doesn't tear down playback state.
///
/// The `PlaybackController` lives here rather than inside the practice screen
/// because both tabs need it — tapping a saved song has to hand it to the
/// player and then bring the practice tab forward.
struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var controller = PlaybackController()
    @State private var tab: TabID = .practice

    private enum TabID {
        case practice, saved
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Practice", systemImage: "guitars", value: .practice) {
                ContentView(controller: controller)
            }

            Tab("Saved", systemImage: "bookmark", value: .saved) {
                SavedSongsView(controller: controller) { tab = .practice }
            }
        }
        .task { controller.configure(modelContext: modelContext) }
    }
}

#Preview {
    RootTabView()
        .modelContainer(try! AppSchema.inMemoryContainer())
}
