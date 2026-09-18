//
//  SongRow.swift
//  MusicMomentum
//

import MusicKit
import SwiftUI

struct SongRow: View {
    let song: Song
    var showsAlbum = false

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = song.artwork {
                ArtworkImage(artwork, width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 48, height: 48)
                    .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        guard showsAlbum, let album = song.albumTitle, !album.isEmpty else {
            return song.artistName
        }
        return "\(song.artistName) — \(album)"
    }
}
