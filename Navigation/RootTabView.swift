import SwiftUI

// MARK: - RootTabView

/// The app's root tab bar: Home, Explore, Search, Library.
///
/// Each tab owns its own `NavigationStack` so push state is preserved when
/// switching tabs. The player bar is overlaid above the tab bar (see
/// `RootView`) so it persists across tabs.
struct RootTabView: View {
    @Binding var selection: TabItem
    @Binding var homePath: NavigationPath
    @Binding var explorePath: NavigationPath
    @Binding var searchPath: NavigationPath
    @Binding var libraryPath: NavigationPath

    let client: any YTMusicClientProtocol

    var body: some View {
        TabView(selection: self.$selection) {
            HomeView(viewModel: HomeViewModel(client: self.client), navigationPath: self.$homePath)
                .tabItem {
                    Label("Home", systemImage: "play.house")
                }
                .tag(TabItem.home)

            ExploreView(viewModel: ExploreViewModel(client: self.client), navigationPath: self.$explorePath)
                .tabItem {
                    Label("Explore", systemImage: "safari")
                }
                .tag(TabItem.explore)

            SearchView(viewModel: SearchViewModel(client: self.client), navigationPath: self.$searchPath)
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(TabItem.search)

            LibraryView(viewModel: LibraryViewModel(client: self.client), navigationPath: self.$libraryPath)
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
