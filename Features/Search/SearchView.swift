import SwiftUI

// MARK: - SearchView

/// Search across songs, albums, artists, and playlists.
///
/// Debounced query + per-section results. Reuses `SongRow` for songs and
/// `SectionShelf`/cards for the rest.
struct SearchView: View {
    @State var viewModel: SearchViewModel
    @Environment(PlayerService.self) private var playerService
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: self.$navigationPath) {
            ScrollView {
                if self.viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.emptyState
                } else {
                    switch self.viewModel.loadingState {
                    case .idle, .loading:
                        LoadingView()
                    case .loaded, .loadingMore:
                        self.resultsView
                    case let .error(error):
                        ErrorView(error: error) {
                            Task { await self.viewModel.searchImmediately() }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestinations(client: self.viewModel.client)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .searchable(text: self.$viewModel.query, prompt: "Songs, albums, artists, playlists")
        .submitLabel(.search)
        .onSubmit(of: .search) {
            Task { await self.viewModel.searchImmediately() }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView.search(text: "")
    }

    @ViewBuilder
    private var resultsView: some View {
        LazyVStack(alignment: .leading, spacing: Theme.spacingXL) {
            let results = self.viewModel.results

            if !results.songs.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacingS) {
                    SectionHeader(title: "Songs")
                    LazyVStack(spacing: 0) {
                        ForEach(results.songs) { song in
                            SongRow(song: song)
                        }
                    }
                }
            }

            if !results.albums.isEmpty {
                SectionShelf(title: "Albums", items: results.albums.map { HomeSectionItem.album($0) })
            }

            if !results.artists.isEmpty {
                SectionShelf(title: "Artists", items: results.artists.map { HomeSectionItem.artist($0) })
            }

            if !results.playlists.isEmpty {
                SectionShelf(title: "Playlists", items: results.playlists.map { HomeSectionItem.playlist($0) })
            }
        }
        .padding(.top, Theme.spacingM)
        .padding(.bottom, 132)
    }

}
