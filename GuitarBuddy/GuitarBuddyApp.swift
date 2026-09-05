//
//  GuitarBuddyApp.swift
//  GuitarBuddy
//
//  Created by Stephen Denekamp on 05/09/2026.
//

import SwiftData
import SwiftUI

@main
struct GuitarBuddyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SongSpeedPreference.self)
    }
}
