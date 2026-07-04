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
                ForEach(self.viewModel.sections) { section in
                    SectionShelf(
                        title: section.title,
                        items: section.items,
                        isChart: section.isChart
                    )
                }
            }
            .padding(.top, Theme.spacingM)
            .padding(.bottom, 132)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

}
