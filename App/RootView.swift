import SwiftUI

// MARK: - RootView

/// Root view that switches between Login (logged out) and the main TabView
/// (logged in), overlaying the player bar and now-playing surface. Mirrors
/// the macOS `MainWindow`'s auth-gating + environment
/// injection, adapted to iOS's single-scene model.
struct RootView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.client) private var client

    @State private var selectedTab: TabItem = .home
    @State private var homePath = NavigationPath()
    @State private var explorePath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var isNowPlayingPresented = false
    @Namespace private var playerTransition

    var body: some View {
        Group {
            switch self.authService.state {
            case .initializing:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loggedOut, .loggingIn:
                LoginView()
            case .loggedIn:
                if let client {
                    self.mainContent(client: client)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task {
            await self.authService.checkLoginStatus()
        }
    }

    /// The logged-in surface: tabs + player bar overlay + now-playing surface.
    @ViewBuilder
    private func mainContent(client: any YTMusicClientProtocol) -> some View {
        ZStack(alignment: .bottom) {
            RootTabView(
                selection: self.$selectedTab,
                homePath: self.$homePath,
                explorePath: self.$explorePath,
                searchPath: self.$searchPath,
                libraryPath: self.$libraryPath,
                client: client
            )
                .hostingPlaylistCoordinators()
                .environment(\.presentNowPlaying) {
                    withAnimation(AppAnimation.spring) {
                        self.isNowPlayingPresented = true
                    }
                }

            // Mini player bar pinned above the tab bar; safe-area-aware.
            PlayerBar(isNowPlayingPresented: self.$isNowPlayingPresented, namespace: self.playerTransition)
                .padding(.bottom, 49) // approx. tab bar height
                .ignoresSafeArea(.keyboard)
                .opacity(self.isNowPlayingPresented ? 0 : 1)
                .allowsHitTesting(!self.isNowPlayingPresented)
                .accessibilityHidden(self.isNowPlayingPresented)

            if self.isNowPlayingPresented {
                NowPlayingView(namespace: self.playerTransition) {
                    withAnimation(AppAnimation.spring) {
                        self.isNowPlayingPresented = false
                    }
                }
                .zIndex(1)
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .environment(\.openArtistPage) { artist in
            self.openArtistPage(artist)
        }
        .tint(Theme.Colors.accent)
        .animation(AppAnimation.spring, value: self.isNowPlayingPresented)
    }

    private func openArtistPage(_ artist: Artist) {
        guard artist.hasNavigableId else { return }

        withAnimation(AppAnimation.spring) {
            self.isNowPlayingPresented = false
        }

        switch self.selectedTab {
        case .home:
            self.homePath.append(artist)
        case .explore:
            self.explorePath.append(artist)
        case .search:
            self.searchPath.append(artist)
        case .library:
            self.libraryPath.append(artist)
        }
    }
}
