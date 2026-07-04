import SwiftUI

// MARK: - ExploreView

/// The Explore feed: new releases, charts, moods. Mirrors HomeView's layout.
struct ExploreView: View {
    @State var viewModel: ExploreViewModel
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: self.$navigationPath) {
            Group {
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
            .navigationTitle("Explore")
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
                    SectionShelf(title: section.title, items: section.items, isChart: section.isChart)
                }
            }
            .padding(.vertical, Theme.spacingM)
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
