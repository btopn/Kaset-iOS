import SwiftUI

// MARK: - ArtistDiscographyView

/// Grid of an artist's full discography (albums / singles / EPs).
struct ArtistDiscographyView: View {
    @State var viewModel: ArtistDiscographyViewModel

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            switch self.viewModel.loadingState {
            case .idle, .loading:
                LoadingView()
            case let .error(error):
                ErrorView(error: error) {
                    Task { await self.viewModel.load() }
                }
            case .loaded, .loadingMore:
                LazyVGrid(columns: self.columns, spacing: Theme.spacingL) {
                    ForEach(self.viewModel.albums) { album in
                        if let playlist = self.navigationPlaylist(for: album) {
                            NavigationLink(value: playlist) {
                                self.albumCard(album)
                            }
                            .buttonStyle(.plain)
                        } else {
                            self.albumCard(album)
                        }
                    }
                }
                .padding(.horizontal, Theme.spacingXL)
            }
        }
        .navigationTitle("Discography")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if self.viewModel.loadingState == .idle {
                await self.viewModel.load()
            }
        }
    }

    private func albumCard(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            ArtworkView(
                url: album.thumbnailURL,
                targetSize: .init(width: 150, height: 150),
                cornerRadius: Theme.cornerRadiusL
            )
            Text(album.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if let year = album.year {
                Text(year)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func navigationPlaylist(for album: Album) -> Playlist? {
        guard album.hasNavigableId else { return nil }
        return Playlist(
            id: album.id,
            title: album.title,
            description: nil,
            thumbnailURL: album.thumbnailURL,
            trackCount: album.trackCount,
            author: Artist.inline(name: album.artistsDisplay, namespace: "album-artist")
        )
    }
}
