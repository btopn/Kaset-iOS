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
            .navigationTitle("Home")
            .navigationDestinations(client: self.viewModel.client)
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.spacingXL) {
                ForEach(self.viewModel.sections) { section in
                    SectionShelf(
                        title: section.title,
                        items: section.items,
                        isChart: section.isChart
                    )
                }
            }
            .padding(.vertical, Theme.spacingM)
        }
    }

    /// Pushes a destination raised by a `SectionCard` tap onto this stack.
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
