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
    var showsOverflowMenu: Bool = true
    var showsPlayNextSwipeAction: Bool = true
    var horizontalPadding: CGFloat = Theme.spacingXL
    var primaryAction: (() -> Void)? = nil

    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(SongLikeStatusManager.self) private var likeStatusManager
    @Environment(\.client) private var client
    @Environment(\.presentNowPlaying) private var presentNowPlaying

    @State private var swipeOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            self.swipeBackground

            HStack(spacing: Theme.spacingM) {
                self.primaryContent
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.performPrimaryAction()
                    }

                if self.showsLikeButton {
                    LikeButton(song: self.song, isRowHovered: false)
                }

                if self.showsOverflowMenu {
                    Menu {
                        self.contextMenu
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Song actions")
                }
            }
            .background(Theme.Colors.background.opacity(self.swipeOffset > 0 ? 0.96 : 0))
            .offset(x: self.swipeOffset)
        }
        .clipped()
        .simultaneousGesture(self.playNextSwipeGesture)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Play")) {
            self.performPrimaryAction()
        }
        .contextMenu {
            self.contextMenu
        }
        .padding(.horizontal, self.horizontalPadding)
        .padding(.vertical, Theme.spacingS)
    }

    private var swipeBackground: some View {
        Label("Play Next", systemImage: "text.insert")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.leading, self.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Theme.Colors.accent.opacity(self.swipeOffset > 0 ? 1 : 0))
            .opacity(self.showsPlayNextSwipeAction && self.swipeOffset > 12 ? 1 : 0)
            .accessibilityHidden(true)
    }

    private var playNextSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard self.showsPlayNextSwipeAction,
                      value.translation.width > 0,
                      abs(value.translation.width) > abs(value.translation.height)
                else { return }

                self.swipeOffset = min(value.translation.width, 92)
            }
            .onEnded { value in
                guard self.showsPlayNextSwipeAction else { return }
                if value.translation.width > 72 || value.predictedEndTranslation.width > 120 {
                    SongActionsHelper.addToQueueNext(self.song, playerService: self.playerService)
                    HapticService.toggle()
                }

                withAnimation(AppAnimation.snappy) {
                    self.swipeOffset = 0
                }
            }
    }

    private var primaryContent: some View {
        HStack(spacing: Theme.spacingM) {
            if let rank {
                Text("\(rank)")
                    .font(.title3.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .center)
            }

            ArtworkView(
                url: self.song.displayThumbnailURL,
                targetSize: .init(width: Theme.ArtworkSize.row, height: Theme.ArtworkSize.row),
                cornerRadius: Theme.cornerRadiusS
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.spacingXS) {
                    Text(self.song.title)
                        .font(.body)
                        .lineLimit(1)

                    if self.song.isExplicit == true {
                        ExplicitBadge()
                    }
                }

                if !self.metadataDisplay.isEmpty {
                    Text(self.metadataDisplay)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.spacingS)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button {
            self.performPrimaryAction()
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

    private func playSong() {
        self.presentNowPlaying()
        Task { await self.playerService.play(song: self.song) }
        HapticService.playback()
    }

    private func performPrimaryAction() {
        if let primaryAction {
            primaryAction()
        } else {
            self.playSong()
        }
    }

    private var metadataDisplay: String {
        let firstArtist = self.song.artists
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !Self.isMetadataLabel($0) } ?? ""
        guard self.showsDuration, self.song.duration != nil else { return firstArtist }
        guard !firstArtist.isEmpty else { return self.song.durationDisplay }
        return "\(firstArtist) · \(self.song.durationDisplay)"
    }

    private static func isMetadataLabel(_ value: String) -> Bool {
        switch value.lowercased() {
        case "album", "song", "single", "ep", "playlist", "podcast", "episode", "video":
            true
        default:
            false
        }
    }
}
