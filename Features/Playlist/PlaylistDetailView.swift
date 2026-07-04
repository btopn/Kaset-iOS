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
    @State private var playlistSearchText = ""

    @Environment(PlayerService.self) private var playerService
    @Environment(\.presentNowPlaying) private var presentNowPlaying

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
                    self.playlistSearchField
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
                    self.presentNowPlaying()
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

    private var playlistSearchField: some View {
        HStack(spacing: Theme.spacingS) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Search in playlist", text: self.$playlistSearchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()

            if !self.playlistSearchText.isEmpty {
                Button {
                    self.playlistSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear playlist search")
            }
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, 10)
        .background(Theme.Colors.surfaceStrong, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.secondary.opacity(0.14), lineWidth: 1)
        }
        .padding(.horizontal, Theme.spacingXL)
    }

    private var tracksList: some View {
        let tracks = self.viewModel.playlistDetail?.tracks ?? []
        let filteredTracks = self.filteredTracksWithIndices(in: tracks)
        return LazyVStack(spacing: 0) {
            if filteredTracks.isEmpty, !tracks.isEmpty {
                EmptyStateView(
                    title: "No Matches",
                    message: "Try a different song, artist, or album.",
                    systemImage: "magnifyingglass"
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.spacingXL)
                .padding(.vertical, Theme.spacingXL)
            } else {
                ForEach(filteredTracks) { item in
                    SongRow(song: item.song, rank: nil)
                        .onAppear {
                            // Load more when nearing the end.
                            if self.playlistSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               item.index == max(0, tracks.count - 5)
                            {
                                Task { await self.viewModel.loadMore() }
                            }
                        }
                }
            }
        }
    }

    private func filteredTracksWithIndices(in tracks: [Song]) -> [PlaylistTrackSearchResult] {
        let query = self.playlistSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return tracks.enumerated().map { PlaylistTrackSearchResult(index: $0.offset, song: $0.element) }
        }

        return tracks.enumerated().compactMap { index, song in
            guard self.playlistSearchFields(for: song).contains(where: { field in
                field.localizedCaseInsensitiveContains(query)
            }) else { return nil }

            return PlaylistTrackSearchResult(index: index, song: song)
        }
    }

    private func playlistSearchFields(for song: Song) -> [String] {
        [
            song.title,
            song.artists.first?.name ?? "",
            song.artistsDisplay,
            song.album?.title ?? "",
        ]
    }
}

private struct PlaylistTrackSearchResult: Identifiable {
    let index: Int
    let song: Song

    var id: String {
        self.song.id
    }
}
