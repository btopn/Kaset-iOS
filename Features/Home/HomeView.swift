import SwiftUI

// MARK: - HomeView

/// The home feed: personalized YouTube Music shelves rendered with the shared
/// `SectionShelf` component. Consumes the ported `HomeViewModel`.
struct HomeView: View {
    @State var viewModel: HomeViewModel
    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @State private var navigationPath = NavigationPath()
    @State private var networkMonitor = NetworkMonitor.shared

    var body: some View {
        NavigationStack(path: self.$navigationPath) {
            Group {
                if !self.networkMonitor.isConnected {
                    ErrorView(
                        title: "No Connection",
                        message: "Please check your internet connection and try again."
                    ) {
                        Task { await self.viewModel.refresh() }
                    }
                } else {
                    switch self.viewModel.loadingState {
                    case .idle, .loading:
                        LoadingView()
                    case .loaded, .loadingMore:
                        self.contentView
                    case let .error(error):
                        ErrorView(error: error) {
                            Task { await self.viewModel.refresh() }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestinations(client: self.viewModel.client)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .task {
            if self.viewModel.loadingState == .idle {
                await self.viewModel.load()
            }
        }
        .refreshable {
            await self.viewModel.refresh()
        }
    }

    private var contentView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.spacingXL) {
                self.homeHeader

                let quickPickSongs = self.quickPickSongs
                let quickPickIDs = Set(quickPickSongs.map { "song-\($0.id)" })

                if !quickPickSongs.isEmpty {
                    HomeCompactSongSection(title: "Quick picks", songs: quickPickSongs)
                }

                ForEach(self.viewModel.sections) { section in
                    let items = section.items.filter { !quickPickIDs.contains($0.id) }
                    if !items.isEmpty {
                        HomeCompactSection(title: section.title, items: Array(items.prefix(6)))
                    }
                }
            }
            .padding(.top, Theme.spacingS)
            .padding(.bottom, 132)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private var homeHeader: some View {
        HStack(spacing: Theme.spacingS) {
            Image(systemName: "play.circle.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.Colors.accent)

            Text("Kaset")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, Theme.spacingXL)
        .padding(.top, Theme.spacingS)
    }

    private var quickPickSongs: [Song] {
        var seen = Set<String>()
        var songs: [Song] = []

        for section in self.viewModel.sections {
            for item in section.items {
                guard case let .song(song) = item, seen.insert(song.id).inserted else { continue }
                songs.append(song)
                if songs.count == 6 { return songs }
            }
        }

        return songs
    }

}

private struct HomeCompactSongSection: View {
    let title: String
    let songs: [Song]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            SectionHeader(title: self.title)
            LazyVStack(spacing: 0) {
                ForEach(self.songs) { song in
                    SongRow(song: song, showsLikeButton: false, showsDuration: false)
                }
            }
        }
    }
}

private struct HomeCompactSection: View {
    let title: String
    let items: [HomeSectionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            SectionHeader(title: self.title)
            LazyVStack(spacing: 0) {
                ForEach(self.items) { item in
                    HomeCompactRow(item: item)
                }
            }
        }
    }
}

private struct HomeCompactRow: View {
    let item: HomeSectionItem

    var body: some View {
        switch self.item {
        case let .song(song):
            SongRow(song: song, showsLikeButton: false, showsDuration: false)
        case let .album(album):
            if let playlist = self.navigationPlaylist(for: album) {
                NavigationLink(value: playlist) {
                    self.rowLabel
                }
                .buttonStyle(.plain)
            } else {
                self.rowLabel
            }
        case let .playlist(playlist):
            NavigationLink(value: playlist) {
                self.rowLabel
            }
            .buttonStyle(.plain)
        case let .artist(artist):
            NavigationLink(value: artist) {
                self.rowLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var rowLabel: some View {
        HStack(spacing: Theme.spacingM) {
            ArtworkView(
                url: self.item.thumbnailURL,
                targetSize: .init(width: Theme.ArtworkSize.row, height: Theme.ArtworkSize.row),
                cornerRadius: self.cornerRadius
            )
            .overlay {
                RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(self.item.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = self.item.homeCardSubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, Theme.spacingXL)
        .padding(.vertical, Theme.spacingS)
        .contentShape(Rectangle())
    }

    private var cornerRadius: CGFloat {
        if case .artist = self.item {
            Theme.ArtworkSize.row / 2
        } else {
            Theme.cornerRadiusS
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
