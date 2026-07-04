import SwiftUI

// MARK: - KasetApp

/// Entry point for Kaset on iOS.
///
/// Wires up the shared services once at launch and injects them into the
/// environment, mirroring the macOS `KasetApp` initializer. The single source
/// of truth for dependency injection.
@main
struct KasetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: - Shared Services

    @State private var authService = AuthService()
    @State private var webKitManager = WebKitManager.shared
    @State private var playerService = PlayerService()
    @State private var sharedClient: any YTMusicClientProtocol
    @State private var accountService: AccountService?
    @State private var notificationService: NotificationService?
    @State private var favoritesManager = FavoritesManager.shared
    @State private var likeStatusManager = SongLikeStatusManager.shared
    @State private var settings = SettingsManager.shared
    @State private var syncedLyricsService: SyncedLyricsService

    init() {
        let auth = AuthService()
        let webkit = WebKitManager.shared
        let player = PlayerService()

        // Build the real client (no UI-test mocking on iOS yet).
        let realClient = YTMusicClient(authService: auth, webKitManager: webkit)

        // Wire up dependencies.
        player.setYTMusicClient(realClient)
        SongLikeStatusManager.shared.setClient(realClient)
        PlayerService.shared = player

        // Account service (brand-account switcher) + brand-id provider.
        let account = AccountService(ytMusicClient: realClient, authService: auth, webKitManager: webkit)
        realClient.brandIdProvider = { [weak account] in account?.currentBrandId }

        // Playlist creation coordinator needs the client for create requests.
        PlaylistCreationCoordinator.shared.configure(client: realClient)

        // Synced lyrics (YTMusic + LRCLib providers).
        let lyrics = SyncedLyricsService(providers: [
            YTMusicSyncedProvider(client: realClient),
            LRCLibProvider(),
        ])

        _authService = State(initialValue: auth)
        _webKitManager = State(initialValue: webkit)
        _playerService = State(initialValue: player)
        _sharedClient = State(initialValue: realClient)
        _accountService = State(initialValue: account)
        _notificationService = State(initialValue: NotificationService(playerService: player))
        _syncedLyricsService = State(initialValue: lyrics)

        // Route lock-screen / Control Center media keys to PlayerService.
        NowPlayingManager.shared.configure(playerService: player)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(self.authService)
                .environment(self.webKitManager)
                .environment(self.playerService)
                .environment(self.favoritesManager)
                .environment(self.likeStatusManager)
                .environment(self.accountService)
                .environment(self.syncedLyricsService)
                .environment(\.client, self.sharedClient)
                .onAppear {
                    // Reference to keep the service alive; SwiftUI would otherwise
                    // release it since it isn't otherwise read here.
                    _ = self.notificationService
                }
                .task {
                    // Fetch accounts for the account switcher once auth settles.
                    // (Login status itself is checked in RootView, which gates on it.)
                    await self.accountService?.fetchAccounts()
                }
        }
    }
}
