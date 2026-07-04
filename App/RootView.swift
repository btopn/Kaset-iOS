import SwiftUI

// MARK: - RootView

/// Root view that switches between Login (logged out) and the main TabView
/// (logged in), overlaying the player bar and presenting the now-playing
/// sheet. Mirrors the macOS `MainWindow`'s auth-gating + environment
/// injection, adapted to iOS's single-scene model.
struct RootView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.client) private var client

    @State private var selectedTab: TabItem = .home
    @State private var isNowPlayingPresented = false

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

    /// The logged-in surface: tabs + player bar overlay + now-playing sheet.
    @ViewBuilder
    private func mainContent(client: any YTMusicClientProtocol) -> some View {
        ZStack(alignment: .bottom) {
            RootTabView(selection: self.$selectedTab, client: client)
                .hostingPlaylistCoordinators()

            // Mini player bar pinned above the tab bar; safe-area-aware.
            PlayerBar(isNowPlayingPresented: self.$isNowPlayingPresented)
                .padding(.bottom, 49) // approx. tab bar height
                .ignoresSafeArea(.keyboard)
        }
        .sheet(isPresented: self.$isNowPlayingPresented) {
            NowPlayingView()
                .presentationDragIndicator(.visible)
        }
    }
}
