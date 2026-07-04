import SwiftUI

// MARK: - TopSongsView

/// Ranked list of an artist's top songs.
struct TopSongsView: View {
    @State var viewModel: TopSongsViewModel

    var body: some View {
        ScrollView {
            switch self.viewModel.loadingState {
            case .idle, .loading:
                LoadingView()
            case let .error(error):
                ErrorView(error: error) {
                    Task { await self.viewModel.load() }
                }
            case .loaded, .loadingMore:
                LazyVStack(spacing: 0) {
                    ForEach(Array(self.viewModel.songs.enumerated()), id: \.element.id) { index, song in
                        SongRow(song: song, rank: index + 1)
                    }
                }
            }
        }
        .navigationTitle("Top Songs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if self.viewModel.loadingState == .idle {
                await self.viewModel.load()
            }
        }
    }
}
