import SwiftUI

// MARK: - HomeView

/// The home feed: personalized YouTube Music shelves rendered with the shared
/// `SectionShelf` component. Consumes the ported `HomeViewModel`.
struct HomeView: View {
    @State var viewModel: HomeViewModel
    @Binding var navigationPath: NavigationPath
    @Environment(SongLikeStatusManager.self) private var likeStatusManager
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
            LazyVStack(alignment: .leading, spacing: Theme.spacingL) {
                self.homeHeader

                let quickPickSongs = self.quickPickSongs

                if !quickPickSongs.isEmpty {
                    HomeSongRailSection(title: "Quick picks", songs: quickPickSongs)
                }

                ForEach(self.viewModel.sections) { section in
                    if !self.isQuickPicksSection(section), !section.items.isEmpty {
                        self.sectionContent(section)
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
        if let quickPicksSection = self.viewModel.sections.first(where: self.isQuickPicksSection) {
            return self.dedupedSongs(in: quickPicksSection.items)
        }

        return self.dedupedSongs(in: self.viewModel.sections.flatMap(\.items))
    }

    private func dedupedSongs(in items: [HomeSectionItem]) -> [Song] {
        var seen = Set<String>()
        var songs: [Song] = []

        for item in items {
            guard case let .song(song) = item, seen.insert(song.videoId).inserted else { continue }
            guard !self.likeStatusManager.isDisliked(song) else { continue }
            songs.append(song)
        }

        return songs
    }

    private func isQuickPicksSection(_ section: HomeSection) -> Bool {
        section.title.localizedCaseInsensitiveContains("quick")
    }

    @ViewBuilder
    private func sectionContent(_ section: HomeSection) -> some View {
        let songs = self.dedupedSongs(in: section.items)
        if self.containsOnlySongs(section.items) {
            if !songs.isEmpty {
                HomeSongRailSection(title: section.title, songs: songs)
            }
        } else {
            SectionShelf(title: section.title, items: section.items, isChart: section.isChart)
        }
    }

    private func containsOnlySongs(_ items: [HomeSectionItem]) -> Bool {
        items.allSatisfy { item in
            if case .song = item { true } else { false }
        }
    }
}

private struct HomeSongRailSection: View {
    private static let rowsPerColumn = 4
    private static let rowHeight: CGFloat = 64

    let title: String
    let songs: [Song]

    @State private var currentPage = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            SectionHeader(title: self.title)

            GeometryReader { proxy in
                let pageWidth = max(280, proxy.size.width - Theme.spacingXL * 2)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.spacingM) {
                        ForEach(Array(self.columns.enumerated()), id: \.offset) { index, column in
                            VStack(spacing: 0) {
                                ForEach(column) { song in
                                    SongRow(
                                        song: song,
                                        showsLikeButton: false,
                                        showsDuration: true,
                                        horizontalPadding: 0
                                    )
                                        .frame(height: Self.rowHeight)
                                }
                            }
                            .frame(width: pageWidth)
                            .background {
                                GeometryReader { pageProxy in
                                    Color.clear.preference(
                                        key: HomeRailPageOffsetPreferenceKey.self,
                                        value: [index: pageProxy.frame(in: .named(self.scrollCoordinateSpace)).minX]
                                    )
                                }
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, Theme.spacingXL)
                }
                .coordinateSpace(name: self.scrollCoordinateSpace)
                .scrollTargetBehavior(.viewAligned)
                .onPreferenceChange(HomeRailPageOffsetPreferenceKey.self) { offsets in
                    self.updateCurrentPage(from: offsets)
                }
            }
            .frame(height: Self.rowHeight * CGFloat(min(Self.rowsPerColumn, max(1, self.songs.count))))

            if self.columns.count > 1 {
                HomeRailPageDots(pageCount: self.columns.count, currentPage: self.currentPage)
                    .padding(.top, Theme.spacingXS)
            }
        }
    }

    private var columns: [[Song]] {
        stride(from: 0, to: self.songs.count, by: Self.rowsPerColumn).map { start in
            Array(self.songs[start ..< min(start + Self.rowsPerColumn, self.songs.count)])
        }
    }

    private var scrollCoordinateSpace: String {
        "home-song-rail-\(self.title)"
    }

    private func updateCurrentPage(from offsets: [Int: CGFloat]) {
        guard let closestPage = offsets.min(by: {
            abs($0.value - Theme.spacingXL) < abs($1.value - Theme.spacingXL)
        })?.key else {
            return
        }

        self.currentPage = min(max(closestPage, 0), max(0, self.columns.count - 1))
    }
}

private struct HomeRailPageDots: View {
    let pageCount: Int
    let currentPage: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0 ..< self.pageCount, id: \.self) { page in
                Circle()
                    .fill(page == self.currentPage ? Theme.Colors.accent : Color.secondary.opacity(0.3))
                    .frame(width: page == self.currentPage ? 6 : 4, height: page == self.currentPage ? 6 : 4)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(AppAnimation.quick, value: self.currentPage)
        .accessibilityHidden(true)
    }
}

private struct HomeRailPageOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
