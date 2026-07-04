import SwiftUI

// MARK: - ExploreView

/// The Explore feed: new releases, charts, moods. Mirrors HomeView's layout.
struct ExploreView: View {
    @State var viewModel: ExploreViewModel
    @Binding var navigationPath: NavigationPath

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
                    SectionShelf(title: section.title, items: section.items, isChart: section.isChart)
                }
            }
            .padding(.top, Theme.spacingM)
            .padding(.bottom, 132)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

}
