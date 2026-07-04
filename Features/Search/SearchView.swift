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
                } else if self.viewModel.showSuggestions {
                    self.suggestionsView
                } else {
                    switch self.viewModel.loadingState {
                    case .idle, .loading:
                        LoadingView()
                    case .loaded, .loadingMore:
                        self.resultsView
                    case let .error(error):
                        ErrorView(error: error) {
                            self.viewModel.searchImmediately()
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestinations(client: self.viewModel.client)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .searchable(text: self.$viewModel.query, prompt: "Songs, albums, artists, playlists")
        .submitLabel(.search)
        .onSubmit(of: .search) {
            self.viewModel.searchImmediately()
        }
        .onChange(of: self.viewModel.query) { _, _ in
            self.viewModel.fetchSuggestions()
            self.viewModel.searchFromTyping()
        }
    }

    private var emptyState: some View {
        Color.clear
            .frame(height: 1)
    }

    @ViewBuilder
    private var resultsView: some View {
        LazyVStack(alignment: .leading, spacing: Theme.spacingXL) {
            let results = self.viewModel.results

            if self.viewModel.shouldShowFilters {
                self.filterChips
            }

            let artistItems = results.artists.map { SearchResultItem.artist($0) }
            if !artistItems.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacingS) {
                    SectionHeader(title: "Artists")
                    LazyVStack(spacing: 0) {
                        ForEach(artistItems) { item in
                            self.resultNavigationRow(item)
                        }
                    }
                }
            }

            let songItems = results.songs.map { SearchResultItem.song($0) }
            if !songItems.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacingS) {
                    SectionHeader(title: "Songs")
                    LazyVStack(spacing: 0) {
                        ForEach(songItems) { item in
                            self.resultNavigationRow(item)
                        }
                    }
                }
            }

            let albumItems = results.albums.map { SearchResultItem.album($0) }
            if !albumItems.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacingS) {
                    SectionHeader(title: "Albums")
                    LazyVStack(spacing: 0) {
                        ForEach(albumItems) { item in
                            self.resultNavigationRow(item)
                        }
                    }
                }
            }

            let playlistItems = results.playlists.map { SearchResultItem.playlist($0) }
            if !playlistItems.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacingS) {
                    SectionHeader(title: "Playlists")
                    LazyVStack(spacing: 0) {
                        ForEach(playlistItems) { item in
                            self.resultNavigationRow(item)
                        }
                    }
                }
            }
        }
        .padding(.top, Theme.spacingM)
        .padding(.bottom, 132)
    }

    private var suggestionsView: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(self.viewModel.suggestions) { suggestion in
                Button {
                    self.viewModel.selectSuggestion(suggestion)
                } label: {
                    HStack(spacing: Theme.spacingM) {
                        Image(systemName: "magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)

                        Text(suggestion.query)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, Theme.spacingXL)
                    .padding(.vertical, Theme.spacingM)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Theme.spacingS)
        .padding(.bottom, 132)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacingS) {
                ForEach(SearchViewModel.SearchFilter.allCases) { filter in
                    Button {
                        self.viewModel.selectedFilter = filter
                    } label: {
                        Text(filter.displayName)
                            .font(.subheadline.weight(self.viewModel.selectedFilter == filter ? .semibold : .regular))
                            .foregroundStyle(self.viewModel.selectedFilter == filter ? .white : .primary)
                            .padding(.horizontal, Theme.spacingM)
                            .padding(.vertical, Theme.spacingS)
                            .compatGlass(
                                interactive: true,
                                tint: self.viewModel.selectedFilter == filter ? Theme.Colors.accent.opacity(0.42) : Theme.Colors.glassTint,
                                in: .capsule
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.spacingXL)
        }
    }

    @ViewBuilder
    private func resultNavigationRow(_ item: SearchResultItem, prominent: Bool = false) -> some View {
        switch item {
        case let .song(song):
            SongRow(song: song, showsLikeButton: !prominent, showsDuration: !prominent)
        case let .artist(artist):
            NavigationLink(value: artist) {
                SearchResultRow(item: item, prominent: prominent)
            }
            .buttonStyle(.plain)
        case let .album(album):
            if let playlist = self.navigationPlaylist(for: album) {
                NavigationLink(value: playlist) {
                    SearchResultRow(item: item, prominent: prominent)
                }
                .buttonStyle(.plain)
            } else {
                SearchResultRow(item: item, prominent: prominent)
            }
        case let .playlist(playlist):
            NavigationLink(value: playlist) {
                SearchResultRow(item: item, prominent: prominent)
            }
            .buttonStyle(.plain)
        case .podcastShow:
            SearchResultRow(item: item, prominent: prominent)
        }
    }

    private func navigationPlaylist(for album: Album) -> Playlist? {
        guard album.hasNavigableId else { return nil }
        return Playlist(
            id: album.id,
            title: album.title,
            description: nil,
            thumbnailURL: album.thumbnailURL,
            trackCount: album.trackCount
        )
    }

}

private struct SearchResultRow: View {
    let item: SearchResultItem
    var prominent = false

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            ArtworkView(
                url: self.item.thumbnailURL,
                targetSize: .init(width: self.artworkSize, height: self.artworkSize),
                cornerRadius: self.cornerRadius
            )
            .overlay {
                RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(self.item.title)
                    .font(self.prominent ? .headline.weight(.semibold) : .body)
                    .foregroundStyle(.primary)
                    .lineLimit(self.prominent ? 2 : 1)

                HStack(spacing: Theme.spacingXS) {
                    Text(self.item.resultType)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.accent)

                    if let subtitle = self.item.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, Theme.spacingXL)
        .padding(.vertical, self.prominent ? Theme.spacingM : Theme.spacingS)
        .contentShape(Rectangle())
    }

    private var artworkSize: CGFloat {
        self.prominent ? 64 : Theme.ArtworkSize.row
    }

    private var cornerRadius: CGFloat {
        if case .artist = self.item {
            self.artworkSize / 2
        } else {
            self.prominent ? Theme.cornerRadiusM : Theme.cornerRadiusS
        }
    }
}
