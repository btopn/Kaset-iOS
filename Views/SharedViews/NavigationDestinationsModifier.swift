import SwiftUI

// MARK: - NavigationDestinationsModifier

/// View modifier that registers the app's push destinations
/// (Playlist, Album, Artist, MoodCategory, TopSongs, ArtistSeeAll).
///
/// A single, centralized router: every feature that wraps its content in a
/// `NavigationStack` calls `.navigationDestinations(client:)` once instead of
/// each view re-declaring its own destinations.
struct NavigationDestinationsModifier: ViewModifier {
    let client: any YTMusicClientProtocol
    let playerBarNavigationAction: PlayerBarNavigationAction
    @Environment(LibraryViewModel.self) private var libraryViewModel: LibraryViewModel?

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Playlist.self) { playlist in
                if MoodCategory.isMoodCategory(playlist.id), let parsed = MoodCategory.parseId(playlist.id) {
                    MoodCategoryDetailView(
                        viewModel: MoodCategoryViewModel(
                            category: MoodCategory(
                                browseId: parsed.browseId,
                                params: parsed.params,
                                title: playlist.title
                            ),
                            client: self.client
                        )
                    )
                } else {
                    PlaylistDetailView(
                        playlist: playlist,
                        viewModel: PlaylistDetailViewModel(playlist: playlist, client: self.client),
                        playerBarNavigationAction: self.playerBarNavigationAction
                    )
                }
            }
            .navigationDestination(for: MoodCategory.self) { category in
                MoodCategoryDetailView(
                    viewModel: MoodCategoryViewModel(category: category, client: self.client)
                )
            }
            .navigationDestination(for: Artist.self) { artist in
                ArtistDetailView(
                    artist: artist,
                    viewModel: ArtistDetailViewModel(
                        artist: artist,
                        client: self.client,
                        libraryViewModel: self.libraryViewModel
                    ),
                    playerBarNavigationAction: self.playerBarNavigationAction
                )
            }
            .navigationDestination(for: TopSongsDestination.self) { destination in
                TopSongsView(viewModel: TopSongsViewModel(destination: destination, client: self.client))
            }
            .navigationDestination(for: ArtistSeeAllDestination.self) { destination in
                switch destination.endpoint.pageType {
                case .discography:
                    ArtistDiscographyView(
                        viewModel: ArtistDiscographyViewModel(destination: destination, client: self.client)
                    )
                case .artist, .playlist:
                    // Artist-episode and playlist destinations route through
                    // other values; fall back to an empty detail.
                    EmptyView()
                }
            }
    }
}

extension View {
    /// Adds the app's shared push destinations. Attach once per `NavigationStack`.
    func navigationDestinations(
        client: any YTMusicClientProtocol,
        playerBarNavigationAction: PlayerBarNavigationAction = .disabled
    ) -> some View {
        modifier(NavigationDestinationsModifier(
            client: client,
            playerBarNavigationAction: playerBarNavigationAction
        ))
    }
}
