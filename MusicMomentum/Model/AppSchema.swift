//
//  AppSchema.swift
//  MusicMomentum
//

import SwiftData

/// The one list of stored models; the app, previews and tests all build
/// their containers from it.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [SavedSong.self, SongMarker.self]

    static func inMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
