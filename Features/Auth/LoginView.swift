import SwiftUI
import WebKit

// MARK: - LoginView

/// Full-screen Google sign-in for YouTube Music.
///
/// Ports Kaset's macOS `LoginSheet` + `LoginWebView` to iOS. Uses an embedded
/// `WKWebView` whose cookies are shared (via `WebKitManager`'s persistent data
/// store) with the playback WebView, so a successful sign-in authenticates
/// playback and the API client immediately.
///
/// Login completion is detected by three converging triggers (mirroring the
/// macOS implementation): navigation to music.youtube.com, the
/// `cookiesDidChange` observable, and a 2s polling backup.
struct LoginView: View {
    @Environment(AuthService.self) private var authService
    @Environment(WebKitManager.self) private var webKitManager

    @State private var isCheckingLogin = false
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            self.header

            LoginWebView(onNavigationToYouTubeMusic: {
                self.checkForSuccessfulLogin()
            })
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: self.webKitManager.cookiesDidChange) { _, _ in
            self.checkForSuccessfulLogin()
        }
        .onAppear {
            self.startPollingForLogin()
        }
        .onDisappear {
            self.pollTask?.cancel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            HStack {
                Text("Sign in to YouTube Music")
                    .font(.headline)
                Spacer()
                if self.isCheckingLogin {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Text("If passkeys don't work, use “Try another way” to sign in with a password.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.spacingL)
        .background(.bar)
    }

    /// Starts a periodic task to check for successful login.
    private func startPollingForLogin() {
        self.pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled {
                    await self.checkForSuccessfulLoginAsync()
                }
            }
        }
    }

    private func checkForSuccessfulLogin() {
        guard !self.isCheckingLogin else { return }
        Task { await self.checkForSuccessfulLoginAsync() }
    }

    private func checkForSuccessfulLoginAsync() async {
        guard !self.isCheckingLogin else { return }
        self.isCheckingLogin = true

        // Small delay to allow cookies to settle.
        try? await Task.sleep(for: .milliseconds(300))

        if let sapisid = await self.webKitManager.getSAPISID() {
            // Force backup cookies immediately so auth survives app restart.
            await self.webKitManager.forceBackupCookies()
            try? await Task.sleep(for: .milliseconds(200))
            self.authService.completeLogin(sapisid: sapisid)
            self.pollTask?.cancel()
        }

        self.isCheckingLogin = false
    }
}

// MARK: - LoginWebView

/// Embedded WKWebView that loads the Google sign-in flow and shares cookies
/// with the playback WebView via `WebKitManager`'s persistent data store.
struct LoginWebView: UIViewRepresentable {
    @Environment(WebKitManager.self) private var webKitManager

    /// Callback when navigation completes to YouTube Music.
    var onNavigationToYouTubeMusic: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationToYouTubeMusic: self.onNavigationToYouTubeMusic)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = self.webKitManager.createSessionSwitchWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = WebKitManager.userAgent
        #if DEBUG
            webView.isInspectable = true
        #endif

        // Load the YouTube Music login page with a continue URL back to music.youtube.com.
        if let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&uilel=3&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26hl%3Den%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_: WKWebView, context _: Context) {
        // No updates needed.
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onNavigationToYouTubeMusic: (() -> Void)?

        init(onNavigationToYouTubeMusic: (() -> Void)?) {
            self.onNavigationToYouTubeMusic = onNavigationToYouTubeMusic
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            if let url = webView.url,
               url.host?.contains("music.youtube.com") == true
            {
                self.onNavigationToYouTubeMusic?()
            }
        }
    }
}
