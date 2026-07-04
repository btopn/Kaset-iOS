import SwiftUI

// MARK: - PlaylistDetailView

/// Detail screen for a playlist or album.
///
/// Reused by Liked Music (the same view with the liked-music playlist) and by
/// album navigation. Consumes the ported `PlaylistDetailViewModel`.
struct PlaylistDetailView: View {
    let playlist: Playlist
    @State var viewModel: PlaylistDetailViewModel
    let playerBarNavigationAction: PlayerBarNavigationAction

    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(SongLikeStatusManager.self) private var likeStatusManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingL) {
                self.header

                switch self.viewModel.loadingState {
                case .idle, .loading:
                    LoadingView()
                case let .error(error):
                    ErrorView(error: error) {
                        Task { await self.viewModel.refresh() }
                    }
                case .loaded, .loadingMore:
                    self.tracksList
                }
            }
            .padding(.bottom, Theme.spacingXXXL)
        }
        .navigationTitle(self.playlist.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = self.playlist.shareURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task {
            if self.viewModel.loadingState == .idle {
                await self.viewModel.load()
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.spacingL) {
            ArtworkView(
                url: self.playlist.thumbnailURL,
                targetSize: .init(width: 160, height: 160),
                cornerRadius: Theme.cornerRadiusL
            )

            VStack(alignment: .leading, spacing: Theme.spacingS) {
                Text(self.playlist.title)
                    .font(.title2.bold())
                    .lineLimit(2)
                if let detail = self.viewModel.playlistDetail, let count = detail.trackCount {
                    Text("\(count) songs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let count = self.playlist.trackCount {
                    Text("\(count) songs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    let songs = self.viewModel.playlistDetail?.tracks ?? []
                    guard !songs.isEmpty else { return }
                    Task {
                        await self.playerService.playQueue(songs, startingAt: 0)
                    }
                    HapticService.playback()
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled((self.viewModel.playlistDetail?.tracks.isEmpty ?? true))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.spacingXL)
        .padding(.top, Theme.spacingS)
    }

    private var tracksList: some View {
        let tracks = self.viewModel.playlistDetail?.tracks ?? []
        return LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song, rank: nil)
                    .onAppear {
                        // Load more when nearing the end.
                        if index == tracks.count - 5 {
                            Task { await self.viewModel.loadMore() }
                        }
                    }
            }
        }
    }
}
