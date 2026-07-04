import Foundation
import os
import Security
import WebKit

// MARK: - WebKitManager

/// Manages WebKit data store for persistent cookies and session management.
@MainActor
@Observable
final class WebKitManager: NSObject, WebKitManagerProtocol {
    /// Shared singleton instance.
    static let shared = WebKitManager(dataStore: .default(), restoresCookies: true)

    /// Creates an isolated manager for unit tests.
    static func makeTestInstance() -> WebKitManager {
        WebKitManager(dataStore: .nonPersistent(), restoresCookies: false)
    }

    /// The persistent website data store used across all WebViews.
    let dataStore: WKWebsiteDataStore

    /// Timestamp of the last cookie change (for observation).
    private(set) var cookiesDidChange: Date = .distantPast

    /// Flag to prevent cookie backups while restoring from Keychain.
    private var isRestoringCookies = false

    /// Task for debouncing cookie change handling.
    private var cookieDebounceTask: Task<Void, Never>?

    /// Task for the one-time startup restore from Keychain into WebKit.
    private var initialCookieRestoreTask: Task<Void, Never>?

    /// Minimum interval between cookie backup operations (in seconds).
    private static let cookieDebounceInterval: Duration = .seconds(5)

    /// The YouTube Music origin URL.
    static let origin = "https://music.youtube.com"

    /// Required cookie name for authentication.
    static let authCookieName = "__Secure-3PAPISID"

    /// Fallback cookie name (non-secure version).
    static let fallbackAuthCookieName = "SAPISID"

    /// Custom user agent to appear as Safari to avoid "browser not supported" errors.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private let logger = DiagnosticsLogger.webKit

    private init(dataStore: WKWebsiteDataStore, restoresCookies: Bool) {
        self.dataStore = dataStore

        super.init()

        // Observe cookie changes
        self.dataStore.httpCookieStore.add(self)

        // Restore auth cookies on startup.
        // Keychain is the source of truth; in DEBUG builds we also export to cookies.dat for tooling.
        if restoresCookies, !UITestConfig.isRunningUnitTests {
            self.initialCookieRestoreTask = Task { @MainActor in
                await self.restoreAuthCookiesFromBackup()
                self.initialCookieRestoreTask = nil
            }
        }

        self.logger.info("WebKitManager initialized with persistent data store")
    }

    /// Restores auth cookies from Keychain to WebKit.
    /// Handles migration from legacy file-based storage on first run.
    private func restoreAuthCookiesFromBackup() async {
        self.isRestoringCookies = true
        defer { isRestoringCookies = false }

        // Wait a moment for WebKit to fully initialize
        try? await Task.sleep(for: .milliseconds(100))

        // Migrate from legacy file-based storage if needed (one-time operation).
        // Perform file I/O off the main actor.
        _ = await Task(priority: .utility) {
            LegacyCookieMigration.migrateIfNeeded()
        }.value

        let existingCookies = await dataStore.httpCookieStore.allCookies()
        self.logger.info("WebKit has \(existingCookies.count) cookies on startup")

        // Load cookies from Keychain.
        // Perform Keychain I/O off the main actor; decode on main actor.
        let archiveData = await Task(priority: .utility) {
            KeychainCookieStorage.loadArchiveData()
        }.value

        guard let archiveData else {
            self.logger.info("No cookies found in Keychain (first run or signed out)")
            return
        }

        let keychainCookies = KeychainCookieStorage.decodeCookies(from: archiveData)
        guard !keychainCookies.isEmpty else {
            self.logger.info("No valid cookies found in Keychain")
            return
        }

        #if DEBUG
            DebugCookieFileExporter.exportAuthCookiesArchiveData(archiveData)
        #endif

        self.logger.info("Restoring \(keychainCookies.count) auth cookies from Keychain")

        // Set each cookie in WebKit
        for cookie in keychainCookies {
            await self.dataStore.httpCookieStore.setCookie(cookie)
        }

        // Verify restore
        let cookies = await dataStore.httpCookieStore.allCookies()
        let hasAuth = cookies.contains { $0.name == "SAPISID" || $0.name == "__Secure-3PAPISID" }

        if hasAuth {
            self.logger.info("✓ Auth cookies restored from Keychain (\(cookies.count) total cookies)")
        } else {
            self.logger.error("✗ Failed to restore auth cookies - Keychain data may be corrupted")
        }
    }

    /// Creates a WebView configuration using the shared persistent data store.
    func createWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = self.dataStore

        configuration.preferences.isElementFullscreenEnabled = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Enable AirPlay for streaming to Apple TV, HomePod, etc.
        configuration.allowsAirPlayForMediaPlayback = true

        return configuration
    }

    /// Creates the minimal WebView configuration used for hidden account-switch
    /// navigations. It deliberately shares only the website data store (cookies)
    /// and attaches nothing else, isolating credential-bearing signin URLs.
    func createSessionSwitchWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = self.dataStore
        return configuration
    }

    /// Waits for the one-time startup cookie restore to finish.
    func waitForInitialCookieRestore() async {
        if let restoreTask = self.initialCookieRestoreTask {
            await restoreTask.value
        }
    }

    /// Retrieves all cookies from the HTTP cookie store.
    func getAllCookies() async -> [HTTPCookie] {
        await self.dataStore.httpCookieStore.allCookies()
    }

    /// Gets cookies for a specific domain.
    /// Uses proper domain matching: exact match or cookie domain with leading dot matches subdomains.
    func getCookies(for domain: String) async -> [HTTPCookie] {
        let allCookies = await getAllCookies()
        let normalizedDomain = domain.lowercased()
        return allCookies.filter { cookie in
            let cookieDomain = cookie.domain.lowercased()
            // Exact match
            if cookieDomain == normalizedDomain {
                return true
            }
            // Cookie domain with leading dot matches the domain and all subdomains
            // e.g., ".youtube.com" matches "music.youtube.com" and "youtube.com"
            if cookieDomain.hasPrefix(".") {
                let withoutDot = String(cookieDomain.dropFirst())
                return normalizedDomain == withoutDot || normalizedDomain.hasSuffix("." + withoutDot)
            }
            // Request domain is a subdomain of cookie domain
            // e.g., cookie for "youtube.com" should match "music.youtube.com"
            if normalizedDomain.hasSuffix("." + cookieDomain) {
                return true
            }
            return false
        }
    }

    /// Builds a Cookie header string for the given domain.
    func cookieHeader(for domain: String) async -> String? {
        let cookies = await getCookies(for: domain)
        guard !cookies.isEmpty else { return nil }

        let headerFields = HTTPCookie.requestHeaderFields(with: cookies)
        return headerFields["Cookie"]
    }

    /// Retrieves the SAPISID cookie value used for authentication.
    /// Checks both secure and non-secure cookie variants.
    func getSAPISID() async -> String? {
        let cookies = await getCookies(for: "youtube.com")
        let allCookies = await getAllCookies()
        self.logger.debug("Checking for SAPISID - total cookies: \(allCookies.count), youtube.com cookies: \(cookies.count)")

        // Try secure cookie first, then fallback to non-secure
        let secureCookie = cookies.first { $0.name == Self.authCookieName }
        let fallbackCookie = cookies.first { $0.name == Self.fallbackAuthCookieName }

        if let cookie = secureCookie ?? fallbackCookie {
            // Log cookie expiration for debugging session issues
            if let expiresDate = cookie.expiresDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                let expiresStr = formatter.string(from: expiresDate)
                let isExpired = expiresDate < Date()
                self.logger.debug("Found \(cookie.name) cookie, expires: \(expiresStr), expired: \(isExpired)")

                if isExpired {
                    self.logger.warning("Auth cookie has expired!")
                    return nil
                }
            } else if cookie.isSessionOnly {
                self.logger.debug("Found \(cookie.name) cookie (session-only, no expiration)")
            }
            return cookie.value
        }

        let cookieNames = cookies.map(\.name).joined(separator: ", ")
        self.logger.debug("No auth cookie found. Available cookies: \(cookieNames)")
        return nil
    }

    /// Checks if the required authentication cookies exist.
    func hasAuthCookies() async -> Bool {
        let sapisid = await getSAPISID()
        return sapisid != nil
    }

    /// Logs all authentication-related cookies for debugging.
    /// Call this when troubleshooting login persistence issues.
    func logAuthCookies() async {
        let cookies = await getCookies(for: "youtube.com")
        let authCookieNames = ["SAPISID", "__Secure-3PAPISID", "SID", "HSID", "SSID", "APISID", "__Secure-1PAPISID"]

        self.logger.info("=== Auth Cookie Diagnostic ===")
        self.logger.info("Total youtube.com cookies: \(cookies.count)")

        for name in authCookieNames {
            if let cookie = cookies.first(where: { $0.name == name }) {
                let expiry: String
                if let date = cookie.expiresDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    expiry = formatter.string(from: date)
                } else if cookie.isSessionOnly {
                    expiry = "session-only"
                } else {
                    expiry = "unknown"
                }
                self.logger.info("✓ \(name): expires \(expiry)")
            } else {
                self.logger.info("✗ \(name): not found")
            }
        }
        self.logger.info("==============================")
    }

    /// Clears all website data (cookies, cache, etc.).
    func clearAllData() async {
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date.distantPast

        self.logger.info("Clearing all WebKit data")

        await self.dataStore.removeData(ofTypes: allTypes, modifiedSince: dateFrom)

        // Also clear cookies from Keychain
        KeychainCookieStorage.deleteCookies()

        self.logger.info("WebKit data cleared successfully")
    }

    /// Forces an immediate save of all YouTube/Google cookies to Keychain.
    /// Call this after successful login to ensure cookies are persisted.
    func forceBackupCookies() async {
        let cookies = await dataStore.httpCookieStore.allCookies()
        self.logger.info("Force backup: found \(cookies.count) total cookies")

        // Filter for YouTube/Google auth cookies
        let authCookies = cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            return domain.hasSuffix("youtube.com") || domain.hasSuffix("google.com")
        }

        self.logger.info("Force backup: \(authCookies.count) YouTube/Google cookies to Keychain")
        guard let archive = KeychainCookieStorage.makeArchiveData(from: authCookies) else { return }

        // Perform Keychain/file I/O off the main actor.
        // Fire-and-forget: failures are handled inside KeychainCookieStorage.
        Task(priority: .utility) {
            _ = KeychainCookieStorage.saveArchiveData(archive.data, cookieCount: archive.cookieCount)
            #if DEBUG
                DebugCookieFileExporter.exportAuthCookiesArchiveData(archive.data)
            #endif
        }
    }
}

// MARK: WKHTTPCookieStoreObserver

extension WebKitManager: WKHTTPCookieStoreObserver {
    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in
            self.cookiesDidChange = Date()

            guard !self.isRestoringCookies else { return }

            // Debounce cookie backup to avoid excessive writes
            // WebKit fires this callback for each individual cookie change,
            // which can result in dozens of calls in rapid succession
            self.cookieDebounceTask?.cancel()
            self.cookieDebounceTask = Task {
                do {
                    try await Task.sleep(for: Self.cookieDebounceInterval)
                } catch is CancellationError {
                    // Task was cancelled (new cookie change came in), skip backup
                    return
                } catch {
                    // Unexpected error during sleep - log and continue with backup
                    self.logger.warning("Unexpected error during cookie debounce: \(error.localizedDescription)")
                }

                // Perform debounced backup
                await self.performCookieBackup(cookieStore: cookieStore)
            }
        }
    }

    /// Performs the actual cookie backup after debouncing.
    private func performCookieBackup(cookieStore: WKHTTPCookieStore) async {
        let cookies = await cookieStore.allCookies()

        // Filter for YouTube/Google auth cookies
        let authCookies = cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            return domain.hasSuffix("youtube.com") || domain.hasSuffix("google.com")
        }

        guard let archive = KeychainCookieStorage.makeArchiveData(from: authCookies) else { return }

        // Perform Keychain/file I/O off the main thread.
        Task.detached(priority: .utility) {
            _ = KeychainCookieStorage.saveArchiveData(archive.data, cookieCount: archive.cookieCount)
            #if DEBUG
                DebugCookieFileExporter.exportAuthCookiesArchiveData(archive.data)
            #endif
        }
    }
}

// MARK: - SessionSwitchError

/// Errors raised while switching the WebView session's active delegated identity.
enum SessionSwitchError: LocalizedError {
    /// The page loaded but its `DATASYNC_ID` did not reflect the expected identity.
    case identityNotApplied(expectedBrandId: String?)
    /// The switch navigation failed to load.
    case navigationFailed(underlying: String)
    /// The switch did not complete within the allotted time.
    case timedOut

    var errorDescription: String? {
        switch self {
        case .identityNotApplied:
            "The account session could not be switched. Please try again."
        case .navigationFailed:
            "Failed to load the account switch page."
        case .timedOut:
            "Switching accounts timed out. Please try again."
        }
    }
}

extension WebKitManager {
    /// Switches the shared cookie session's active delegated identity by
    /// navigating a transient WebView to a server-issued account-switch URL.
    ///
    /// History is recorded by the playback page's own stats pings, which
    /// attribute to the identity baked into the served document's
    /// `ytcfg.DATASYNC_ID` (`"<delegatedSessionId>||<userSessionId>"` for a brand,
    /// `"<userSessionId>||"` for primary). Navigating the brand's `signinUrl`
    /// (which carries `&pageid=<brandId>`) re-points that identity for the single
    /// shared `WKWebsiteDataStore`, so subsequent watch loads — and their history
    /// pings — attribute to the brand.
    ///
    /// The method is verification-gated: it reads `DATASYNC_ID` after the
    /// navigation settles and throws ``SessionSwitchError/identityNotApplied(expectedBrandId:)``
    /// unless the result matches `expectedBrandId` (or, for `nil`, an empty
    /// delegated half indicating the primary identity). Callers should perform
    /// this switch *before* committing the new account so a failure can be
    /// surfaced and reverted rather than silently recording to the wrong account.
    ///
    /// - Parameters:
    ///   - signinURL: The server-issued `accountSigninToken.signinUrl`.
    ///   - expectedBrandId: The brand pageId to verify, or `nil` for the primary.
    func switchSessionIdentity(to signinURL: URL, expectedBrandId: String?) async throws {
        self.logger.info("Switching session identity (expecting \(expectedBrandId ?? "primary"))")
        guard AccountsListParser.isAllowedSigninURL(signinURL) else {
            throw SessionSwitchError.navigationFailed(underlying: "Refusing non-YouTube signin URL")
        }

        let configuration = self.createSessionSwitchWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.userAgent

        // Keep the navigation driver alive for the lifetime of the load.
        let driver = SessionSwitchNavigationDriver()
        webView.navigationDelegate = driver

        defer {
            webView.navigationDelegate = nil
            webView.stopLoading()
        }

        // Bail before mutating the shared cookie session if already cancelled
        // (e.g. a stale launch pin superseded by a newer switch).
        try Task.checkCancellation()

        do {
            try await driver.load(signinURL, in: webView, timeout: .seconds(20))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SessionSwitchError {
            throw error
        } catch {
            throw SessionSwitchError.navigationFailed(underlying: error.localizedDescription)
        }

        // The page's ytcfg may be emitted slightly after didFinish; poll briefly.
        // Note: the navigation above is the session MUTATION; this poll is
        // read-only verification. Correctness across concurrent pins relies on
        // ordering (the surviving navigation runs last), not on cancellation —
        // stopLoading() cannot revert cookies already set mid-redirect.
        for attempt in 0 ..< 5 {
            if let dataSyncId = try? await Self.readDataSyncId(from: webView),
               Self.dataSyncId(dataSyncId, matches: expectedBrandId)
            {
                self.logger.info("Session identity switch verified")
                return
            }
            if attempt < 4 {
                // Use a throwing sleep so cancellation breaks the poll loop.
                try await Task.sleep(for: .milliseconds(400))
            }
        }

        self.logger.error("Session identity switch could not be verified")
        throw SessionSwitchError.identityNotApplied(expectedBrandId: expectedBrandId)
    }

    /// Reads `ytcfg.DATASYNC_ID` from a loaded WebView.
    private static func readDataSyncId(from webView: WKWebView) async throws -> String? {
        let script = """
        (function() {
            try {
                if (window.ytcfg && typeof window.ytcfg.get === 'function') {
                    return window.ytcfg.get('DATASYNC_ID') || '';
                }
                if (window.ytcfg && window.ytcfg.data_) {
                    return window.ytcfg.data_['DATASYNC_ID'] || '';
                }
            } catch (e) {}
            return '';
        })();
        """
        let result = try await webView.evaluateJavaScript(script)
        return result as? String
    }

    /// Returns `true` when a `DATASYNC_ID` reflects the expected identity.
    ///
    /// `DATASYNC_ID` is `"<delegatedSessionId>||<userSessionId>"` for a brand
    /// (delegated/secondary channel) and `"<userSessionId>||"` for the primary
    /// account — i.e. the primary has a non-empty first half and an empty second
    /// half. A blank or malformed value (e.g. `""` or `"||"`, which the page JS
    /// returns when `ytcfg` has not populated yet) is treated as *no match* for
    /// either identity, so an unread page never falsely "verifies" as primary.
    static func dataSyncId(_ dataSyncId: String, matches expectedBrandId: String?) -> Bool {
        // A well-formed value has exactly two "||"-separated halves with a
        // non-empty first half (the user/delegated session id).
        let parts = dataSyncId.components(separatedBy: "||")
        guard parts.count == 2, !parts[0].isEmpty else {
            return false
        }
        let firstHalf = parts[0]
        let hasUserSessionSuffix = !parts[1].isEmpty
        // delegatedSessionId is present only for a secondary (brand) identity:
        // "<delegated>||<user>". Primary is "<user>||" (empty second half).
        let delegatedSessionId: String? = hasUserSessionSuffix ? firstHalf : nil
        if let expectedBrandId {
            return delegatedSessionId == expectedBrandId
        }
        return delegatedSessionId == nil
    }
}

// MARK: - SessionSwitchNavigationDriver

/// Drives a one-shot navigation to completion for ``WebKitManager/switchSessionIdentity(to:expectedBrandId:)``.
///
/// Bridges `WKNavigationDelegate` callbacks into a single awaitable result and
/// enforces a timeout so a hung redirect chain cannot block the switch forever.
@MainActor
private final class SessionSwitchNavigationDriver: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false
    private var timeoutTask: Task<Void, Never>?

    func load(_ url: URL, in webView: WKWebView, timeout: Duration) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // The enclosing Task may have been cancelled between the call and
                // this body running; bail out immediately if so.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                self.timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard let self, !self.finished else { return }
                    self.complete(with: .failure(SessionSwitchError.timedOut))
                }
                webView.load(URLRequest(url: url))
            }
        } onCancel: {
            // Cooperative cancellation: resolve promptly with CancellationError so
            // a stale pin does not block a newer switch for the full navigation.
            Task { @MainActor [weak self] in
                self?.complete(with: .failure(CancellationError()))
            }
        }
    }

    private func complete(with result: Result<Void, Error>) {
        guard !self.finished else { return }
        self.finished = true
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        self.complete(with: .success(()))
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        self.complete(with: .failure(SessionSwitchError.navigationFailed(underlying: error.localizedDescription)))
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        self.complete(with: .failure(SessionSwitchError.navigationFailed(underlying: error.localizedDescription)))
    }
}
