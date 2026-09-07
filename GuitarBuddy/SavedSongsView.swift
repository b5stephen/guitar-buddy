//
//  SavedSongsView.swift
//  GuitarBuddy
//

import SwiftUI

/// Placeholder for the saved songs list — the real one lands later.
struct SavedSongsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No saved songs yet",
                systemImage: "bookmark",
                description: Text("Songs you save while practising will show up here.")
            )
            .navigationTitle("Saved")
        }
    }
}

#Preview {
    SavedSongsView()
}
