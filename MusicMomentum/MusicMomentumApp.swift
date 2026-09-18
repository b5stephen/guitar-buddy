//
//  MusicMomentumApp.swift
//  MusicMomentum
//
//  Created by Stephen Denekamp on 05/09/2026.
//

import SwiftData
import SwiftUI

@main
struct MusicMomentumApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: AppSchema.models)
    }
}
