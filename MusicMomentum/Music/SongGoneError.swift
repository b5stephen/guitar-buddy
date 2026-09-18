import Foundation

/// A saved song that Apple Music no longer has, in the library or the catalog.
struct SongGoneError: LocalizedError {
    var errorDescription: String? {
        "That song isn't in your library or on Apple Music any more."
    }
}
