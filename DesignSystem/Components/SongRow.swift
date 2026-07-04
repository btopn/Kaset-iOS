import SwiftUI

// MARK: - SongRow

/// The one reusable track row.
///
/// Used by every list of songs: History, Search results, Playlist tracks,
/// Liked Music, artist Top Songs, etc. Renders artwork, title, artist/album
/// subtitle, duration, an optional rank, an optional like button, and the
/// standard context menu (play next/last, add to playlist, share, like).
///
/// Reuse over duplication: features configure this row rather than rolling
/// their own.
struct SongRow: View {
    let song: Song
    var rank: Int? = nil
    var showsLikeButton: Bool = true
    var showsDuration: Bool = true

    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(SongLikeStatusManager.self) private var likeStatusManager
    @Environment(\.client) private var client

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            if let rank {
                Text("\(rank)")
                    .font(.title3.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .center)
            } else {
                ArtworkView(
                    url: self.song.thumbnailURL ?? self.song.fallbackThumbnailURL,
                    targetSize: .init(width: Theme.ArtworkSize.row, height: Theme.ArtworkSize.row),
                    cornerRadius: Theme.cornerRadiusS
                )
            }

            if rank != nil {
                ArtworkView(
                    url: self.song.thumbnailURL ?? self.song.fallbackThumbnailURL,
                    targetSize: .init(width: Theme.ArtworkSize.row, height: Theme.ArtworkSize.row),
                    cornerRadius: Theme.cornerRadiusS
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.spacingXS) {
                    Text(self.song.title)
                        .font(.body)
                        .lineLimit(1)

                    if self.song.isExplicit == true {
                        ExplicitBadge()
                    }
                }
                Text(self.song.artistsDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if self.showsLikeButton {
                LikeButton(song: self.song, isRowHovered: false)
            }

            if self.showsDuration, let _ = self.song.duration {
                Text(self.song.durationDisplay)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .padding(.leading, Theme.spacingXS)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await self.playerService.play(song: self.song) }
            HapticService.playback()
        }
        .contextMenu {
            self.contextMenu
        }
        .padding(.horizontal, Theme.spacingXL)
        .padding(.vertical, Theme.spacingS)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button {
            Task { await self.playerService.play(song: self.song) }
        } label: {
            Label("Play", systemImage: "play.fill")
        }

        AddToQueueContextMenu(song: self.song, playerService: self.playerService)

        if let client {
            AddToPlaylistContextMenu(song: self.song, client: client)
        }

        Divider()

        LikeDislikeContextMenu(song: self.song, likeStatusManager: self.likeStatusManager)

        Divider()

        ShareContextMenu.menuItem(for: self.song)
    }
}
