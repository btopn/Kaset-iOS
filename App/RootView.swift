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
            RootTabView(selection: self.$selectedTab, client: client)
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
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .animation(AppAnimation.spring, value: self.isNowPlayingPresented)
    }
}
