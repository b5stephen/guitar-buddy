//
//  RootTabView.swift
//  GuitarBuddy
//

import SwiftData
import SwiftUI

/// The app's top level: practice on one tab, the songs you've saved on the
/// other. `TabView` keeps both tabs alive, so switching away from practice
/// doesn't tear down playback state.
struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Practice", systemImage: "guitars") {
                ContentView()
            }

            Tab("Saved", systemImage: "bookmark") {
                SavedSongsView()
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: SongSpeedPreference.self, inMemory: true)
}
