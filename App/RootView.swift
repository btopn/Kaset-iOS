import SwiftUI

// MARK: - RootView

/// Root view that switches between Login (logged out) and the main TabView
/// (logged in), hosting the shared services and the player bar overlay.
///
/// Mirrors the macOS `MainWindow`'s responsibility of gating on auth state and
/// injecting the environment, adapted to iOS's single-scene model.
struct RootView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.client) private var client

    @State private var selectedTab: TabItem = .home

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
                    RootTabView(selection: self.$selectedTab, client: client)
                        .hostingPlaylistCoordinators()
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
}
