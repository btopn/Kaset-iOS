import SwiftUI

// MARK: - MoodCategoryDetailView

/// Detail screen for a mood/genre category. Renders the category's shelves.
struct MoodCategoryDetailView: View {
    @State var viewModel: MoodCategoryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingL) {
                switch self.viewModel.loadingState {
                case .idle, .loading:
                    LoadingView()
                case let .error(error):
                    ErrorView(error: error) {
                        Task { await self.viewModel.load() }
                    }
                case .loaded, .loadingMore:
                    ForEach(self.viewModel.sections) { section in
                        SectionShelf(
                            title: section.title,
                            items: section.items
                        )
                    }
                }
            }
            .padding(.vertical, Theme.spacingM)
        }
        .navigationTitle(self.viewModel.category.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if self.viewModel.loadingState == .idle {
                await self.viewModel.load()
            }
        }
    }
}
