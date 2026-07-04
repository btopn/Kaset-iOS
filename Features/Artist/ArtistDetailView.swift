import SwiftUI

// MARK: - ArtistDetailView

/// Detail screen for an artist.
///
/// Shows the artist's hero artwork, top songs, albums, and related sections.
/// Consumes the ported `ArtistDetailViewModel`.
struct ArtistDetailView: View {
    let artist: Artist
    @State var viewModel: ArtistDetailViewModel
    let playerBarNavigationAction: PlayerBarNavigationAction

    @Environment(PlayerService.self) private var playerService
    @Environment(\.client) private var client

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
                    self.content
                }
            }
            .padding(.bottom, Theme.spacingXXXL)
        }
        .navigationTitle(self.artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if self.viewModel.loadingState == .idle {
                await self.viewModel.load()
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.spacingL) {
            if let url = self.artist.thumbnailURL {
                ArtworkView(
                    url: url,
                    targetSize: .init(width: 120, height: 120),
                    cornerRadius: 60
                )
            }
            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                Text(self.artist.name)
                    .font(.title.bold())
                if let subtitle = self.artist.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let detail = self.viewModel.artistDetail, let desc = detail.description {
                    Text(desc)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.spacingXL)
    }

    @ViewBuilder
    private var content: some View {
        if let detail = self.viewModel.artistDetail {
            if !detail.songs.isEmpty {
                SectionHeader(title: detail.songsSectionTitle ?? "Top Songs")
                LazyVStack(spacing: 0) {
                    ForEach(Array(detail.songs.enumerated()), id: \.element.id) { index, song in
                        SongRow(song: song, rank: index + 1)
                    }
                }
            }

            if !detail.albums.isEmpty {
                SectionShelf(
                    title: "Albums",
                    items: detail.albums.map { HomeSectionItem.album($0) }
                )
                .padding(.top, Theme.spacingL)
            }

            ForEach(detail.orderedSections) { section in
                if case let .albums(albums) = section.content, !albums.isEmpty {
                    SectionShelf(
                        title: section.title,
                        items: albums.map { HomeSectionItem.album($0) }
                    )
                    .padding(.top, Theme.spacingL)
                }
            }
        }
    }
}
