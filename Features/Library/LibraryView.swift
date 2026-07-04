import SwiftUI

// MARK: - LibraryView

/// The user's YouTube Music library: playlists and followed artists.
///
/// Supports create/delete playlist (via the centralized coordinators) and
/// opens playlist/artist detail on tap.
struct LibraryView: View {
    @State var viewModel: LibraryViewModel
    @Environment(\.client) private var client
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: self.$navigationPath) {
            ScrollView {
                switch self.viewModel.loadingState {
                case .idle, .loading:
                    LoadingView()
                case let .error(error):
                    ErrorView(error: error) {
                        Task { await self.viewModel.refresh() }
                    }
                case .loaded, .loadingMore:
                    self.contentView
                }
            }
            .navigationTitle("Library")
            .navigationDestinations(client: self.viewModel.client)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        PlaylistCreationCoordinator.shared.request(
                            message: "Create a private playlist."
                        ) { _ in
                            Task { await self.viewModel.refresh() }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task {
            if self.viewModel.loadingState == .idle {
                await self.viewModel.load()
            }
        }
        .refreshable {
            await self.viewModel.refresh()
        }
        .onChange(of: NavigationBus.shared.pendingDestination) { _, _ in
            self.consumePendingDestination()
        }
    }

    private var contentView: some View {
        LazyVStack(alignment: .leading, spacing: Theme.spacingXL) {
            if !self.viewModel.playlists.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacingM) {
                    SectionHeader(title: "Playlists")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: Theme.spacingM) {
                            ForEach(self.viewModel.playlists) { playlist in
                                self.libraryPlaylistCard(playlist)
                            }
                        }
                        .padding(.horizontal, Theme.spacingXL)
                    }
                }
            }

            if !self.viewModel.artists.isEmpty {
                SectionShelf(title: "Artists", items: self.viewModel.artists.map { HomeSectionItem.artist($0) })
            }
        }
        .padding(.vertical, Theme.spacingM)
    }

    private func libraryPlaylistCard(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            ArtworkView(
                url: playlist.thumbnailURL,
                targetSize: .init(width: Theme.ArtworkSize.cardLarge, height: Theme.ArtworkSize.cardLarge),
                cornerRadius: Theme.cornerRadiusL
            )
            Text(playlist.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(width: Theme.ArtworkSize.cardLarge, alignment: .leading)
        }
        .contextMenu {
            if playlist.canDelete, let client {
                Button(role: .destructive) {
                    PlaylistDeletionCoordinator.shared.request(
                        playlist: playlist,
                        client: client,
                        libraryViewModel: self.viewModel
                    ) {
                        Task { await self.viewModel.refresh() }
                    }
                } label: {
                    Label("Delete Playlist", systemImage: "trash")
                }
            }
            ShareContextMenu.menuItem(for: playlist)
        }
        .onTapGesture {
            NavigationBus.shared.openPlaylist(playlist)
        }
    }

    private func consumePendingDestination() {
        guard let destination = NavigationBus.shared.consume() else { return }
        switch destination {
        case let .playlist(playlist):
            self.navigationPath.append(playlist)
        case let .artist(artist):
            self.navigationPath.append(artist)
        case let .mood(mood):
            self.navigationPath.append(mood)
        case .album:
            break
        }
    }
}
