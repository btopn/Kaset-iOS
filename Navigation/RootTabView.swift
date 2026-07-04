import SwiftUI

// MARK: - RootTabView

/// The app's root tab bar: Home, Explore, Search, Library.
///
/// Each tab owns its own `NavigationStack` so push state is preserved when
/// switching tabs. The player bar is overlaid above the tab bar (see
/// `RootView`) so it persists across tabs.
struct RootTabView: View {
    @Binding var selection: TabItem
    let client: any YTMusicClientProtocol

    @State private var homePath = NavigationPath()
    @State private var explorePath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var libraryPath = NavigationPath()

    var body: some View {
        TabView(selection: self.$selection) {
            HomeView(viewModel: HomeViewModel(client: self.client))
                .tabItem {
                    Label("Home", systemImage: "play.house")
                }
                .tag(TabItem.home)

            ExploreView(viewModel: ExploreViewModel(client: self.client))
                .tabItem {
                    Label("Explore", systemImage: "safari")
                }
                .tag(TabItem.explore)

            SearchView(viewModel: SearchViewModel(client: self.client))
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(TabItem.search)

            LibraryView(viewModel: LibraryViewModel(client: self.client))
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(TabItem.library)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .toolbarBackground(Theme.Colors.background.opacity(0.78), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .tint(Theme.Colors.accent)
    }
}
