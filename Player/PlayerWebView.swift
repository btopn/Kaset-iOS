// swiftlint:disable file_length
import os
import SwiftUI
import UIKit
import WebKit

// MARK: - PlayerWebView

/// SwiftUI wrapper that hosts the singleton YouTube Music playback WebView.
///
/// Ports Kaset's macOS `MiniPlayerWebView` (`NSViewRepresentable`) to iOS
/// (`UIViewRepresentable`). The underlying `SingletonPlayerWebView` singleton is
/// the single source of truth for audio — there is exactly one `WKWebView`
/// playing DRM YouTube Music audio for the whole app lifetime.
struct PlayerWebView: UIViewRepresentable {
    @Environment(WebKitManager.self) private var webKitManager
    @Environment(PlayerService.self) private var playerService

    /// The video ID to play.
    let videoId: String

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)

        // Get or create the singleton WebView.
        let webView = SingletonPlayerWebView.shared.getWebView(
            webKitManager: self.webKitManager,
            playerService: self.playerService
        )

        // Ensure the WebView is installed in this container.
        SingletonPlayerWebView.shared.ensureInHierarchy(container: container)

        // Load the video if needed.
        SingletonPlayerWebView.shared.loadVideo(videoId: self.videoId)

        // Reference the webView so the compiler doesn't warn about the unused
        // local; the singleton owns its lifetime, not this view.
        _ = webView
        return container
    }

    func updateUIView(_ container: UIView, context _: Context) {
        SingletonPlayerWebView.shared.ensureInHierarchy(container: container)
    }

    static func dismantleUIView(_: UIView, coordinator _: ()) {
        // The WebView is owned by SingletonPlayerWebView.shared and persists.
    }
}

// MARK: - SingletonPlayerWebView

/// Manages a single WebView instance for the entire app lifetime.
/// This ensures there's only ever ONE WebView playing audio.
///
/// Extensions provide:
/// - Playback controls (`PlayerWebView+PlaybackControls.swift`)
/// - Observer script (`PlayerWebView+ObserverScript.swift`)
/// - Playback preferences (`PlayerWebView+PlaybackPreferences.swift`)
/// - Playback audio quality (`PlayerWebView+PlaybackAudioQuality.swift`)
@MainActor
final class SingletonPlayerWebView {
    static let shared = SingletonPlayerWebView()

    private(set) var webView: WKWebView?
    weak var webKitManager: WebKitManager?
    var currentVideoId: String?
    var coordinator: Coordinator?
    let logger = DiagnosticsLogger.player
    private var loadGeneration = 0

    /// How `loadVideo` behaves when Swift already tracks a `videoId` (repeat-one vs queue drift recovery).
    enum VideoLoadStrategy: Equatable {
        /// Skip navigation when `videoId` matches `currentVideoId`.
        case standard
        /// Same `videoId` as tracked: `seek(0)` + play only (fast). Different id: full watch URL load.
        case preferInPlaceWhenSameVideoId
        /// Same `videoId` as tracked: full `webView.load` (DOM out of sync with Swift). Different id: full load.
        case forceFullPageWhenSameVideoId
    }

    var mediaControlUsesNextPrev: Bool
    var playbackAudioQuality: SettingsManager.PlaybackAudioQuality

    /// Native timer that re-asserts the media-key override while backgrounded.
    /// See `beginBackgroundMediaControlReassertion()` (no-op on iOS).
    var mediaControlReassertTimer: Timer?

    /// Tracks if lyrics high-frequency polling should be active.
    /// Used to restore polling after full-page navigation.
    var isLyricsPollActive = false

    private init() {
        self.mediaControlUsesNextPrev = SettingsManager.shared.mediaControlStyle == .nextPreviousTrack
        self.playbackAudioQuality = SettingsManager.shared.playbackAudioQuality
    }

    /// Get or create the singleton WebView.
    func getWebView(
        webKitManager: WebKitManager,
        playerService: PlayerService
    ) -> WKWebView {
        if let existing = webView {
            return existing
        }

        self.logger.info("Creating singleton WebView")

        // Create coordinator.
        self.coordinator = Coordinator(playerService: playerService)

        let configuration = webKitManager.createWebViewConfiguration()

        // Add script message handler.
        configuration.userContentController.add(self.coordinator!, name: "singletonPlayer")

        // Dynamic startup state is refreshed before each full page load so the
        // next document gets current volume/autoplay flags at document start.
        self.installUserScripts(
            on: configuration.userContentController,
            isRestoringPlaybackSession: playerService.isRestoringPlaybackSession,
            targetVolume: playerService.volume
        )

        let newWebView = WKWebView(frame: .zero, configuration: configuration)
        newWebView.navigationDelegate = self.coordinator
        newWebView.customUserAgent = WebKitManager.userAgent
        self.webKitManager = webKitManager

        #if DEBUG
            newWebView.isInspectable = true
        #endif

        // Allow inline media to autoplay (audio) without a per-gesture prompt.
        newWebView.configuration.mediaTypesRequiringUserActionForPlayback = []

        self.webView = newWebView
        return newWebView
    }

    /// Ensures the WebView is installed in the given container's view hierarchy.
    func ensureInHierarchy(container: UIView) {
        guard let webView else { return }
        guard webView.superview !== container else { return }
        webView.removeFromSuperview()
        container.addSubview(webView)

        // Use autoresizing to match container size.
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    /// Starts high-frequency polling for synced lyrics.
    func startLyricsPoll() {
        self.isLyricsPollActive = true
        self.webView?.evaluateJavaScript("if (window.startLyricsPoll) { window.startLyricsPoll(); }")
    }

    /// Stops high-frequency polling for synced lyrics.
    func stopLyricsPoll() {
        self.isLyricsPollActive = false
        self.webView?.evaluateJavaScript("if (window.stopLyricsPoll) { window.stopLyricsPoll(); }")
    }

    /// Load a video, stopping any currently playing audio first.
    /// Note: Full page navigation destroys the video element; same-id restarts use ``restartInPlaceFromBeginning()`` when possible.
    /// AirPlay connections will be lost on full navigation but the auto-reconnect picker will appear.
    func loadVideo(videoId: String, strategy: VideoLoadStrategy = .standard) {
        guard let webView else {
            self.logger.error("loadVideo called but webView is nil")
            return
        }

        let previousVideoId = self.currentVideoId

        switch strategy {
        case .standard:
            if videoId == previousVideoId {
                self.logger.debug("Video \(videoId) already loaded, skipping")
                return
            }
        case .preferInPlaceWhenSameVideoId:
            if videoId == previousVideoId {
                self.logger.debug("In-place restart for \(videoId) (same id — avoid full page reload)")
                self.restartInPlaceFromBeginning()
                return
            }
        case .forceFullPageWhenSameVideoId:
            if videoId == previousVideoId {
                self.logger.info("Force full navigation for \(videoId) (DOM/WebView resync)")
            }
        }

        if videoId != previousVideoId {
            self.logger.info("Loading video: \(videoId) (was: \(previousVideoId ?? "none"))")
        }

        // Update currentVideoId immediately to prevent duplicate loads.
        self.currentVideoId = videoId
        self.loadGeneration &+= 1
        let generation = self.loadGeneration

        // Get current volume from PlayerService via coordinator.
        let currentVolume = self.coordinator?.playerService.volume ?? 1.0
        let isRestoringPlaybackSession = self.coordinator?.playerService.isRestoringPlaybackSession ?? false
        self.logger.info("Will apply volume \(currentVolume) after page load")

        self.installUserScripts(
            on: webView.configuration.userContentController,
            isRestoringPlaybackSession: isRestoringPlaybackSession,
            targetVolume: currentVolume
        )

        // Stop current playback first, then load new video. For a forced
        // full-page navigation (e.g. an identity-switch reload) skip pausing the
        // OLD <video>: the navigation tears it down anyway, and the pause event
        // would emit a stale STATE_UPDATE from the outgoing page that can be
        // mis-reconciled against a restored session before the new document loads.
        let urlToLoad = URL(string: "https://music.youtube.com/watch?v=\(videoId)")!
        let skipPrenavPause = (strategy == .forceFullPageWhenSameVideoId && videoId == previousVideoId)
        if skipPrenavPause {
            webView.evaluateJavaScript("window.__kasetTargetVolume = \(currentVolume);", completionHandler: nil)
            webView.load(URLRequest(url: urlToLoad))
            return
        }
        let prenavScript = "document.querySelector('video')?.pause();"
        webView.evaluateJavaScript("\(prenavScript)void 0;") { [weak self] _, _ in
            guard let self, let webView = self.webView else { return }
            guard self.loadGeneration == generation, self.currentVideoId == videoId else { return }

            // Keep the current page's target volume fresh until the new document
            // finishes loading and gets the same value from didFinish.
            let prepareScript = "window.__kasetTargetVolume = \(currentVolume);"
            webView.evaluateJavaScript(prepareScript, completionHandler: nil)

            webView.load(URLRequest(url: urlToLoad))
        }
    }

    /// Returns the JS snippet that hands the autoplay intent to the freshly loaded
    /// page's window. Restored sessions suppress autoplay so the reconcile path
    /// resumes at the saved seek rather than at 0s.
    nonisolated static func autoplayIntentScript(isRestoringPlaybackSession: Bool) -> String {
        "window.__kasetAutoplayPending = \(isRestoringPlaybackSession ? "false" : "true");"
    }

    nonisolated static func pageBootstrapScript(
        isRestoringPlaybackSession: Bool,
        targetVolume: Double
    ) -> String {
        let clampedVolume = if targetVolume.isFinite {
            min(max(targetVolume, 0), 1)
        } else {
            1.0
        }

        return """
            \(Self.autoplayIntentScript(isRestoringPlaybackSession: isRestoringPlaybackSession))
            window.__kasetTargetVolume = \(clampedVolume);
        """
    }

    private func installUserScripts(
        on contentController: WKUserContentController,
        isRestoringPlaybackSession: Bool,
        targetVolume: Double
    ) {
        contentController.removeAllUserScripts()

        // Autoplay intent must exist before media lifecycle events like `canplay`.
        // `didFinish` is too late on fast or cached player loads.
        let pageBootstrapScript = WKUserScript(
            source: Self.pageBootstrapScript(
                isRestoringPlaybackSession: isRestoringPlaybackSession,
                targetVolume: targetVolume
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(pageBootstrapScript)

        // Keep the page preference in sync before any page script reads localStorage.
        let mediaControlBootstrapScript = WKUserScript(
            source: self.mediaControlBootstrapScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(mediaControlBootstrapScript)

        let playbackAudioQualityBootstrapScript = WKUserScript(
            source: self.playbackAudioQualityBootstrapScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(playbackAudioQualityBootstrapScript)

        // Inject mediaSession override at document end without allowing duplicate RAF loops.
        let mediaOverrideScript = WKUserScript(
            source: Self.mediaControlOverrideScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(mediaOverrideScript)

        // Apply preferred playback audio quality at document end and after player recreation.
        let playbackAudioQualityOverrideScript = WKUserScript(
            source: Self.playbackAudioQualityOverrideScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(playbackAudioQualityOverrideScript)

        // Inject observer script (at document end).
        let script = WKUserScript(
            source: Self.observerScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(script)
    }

    func refreshInstalledUserScripts() {
        guard let webView else { return }

        let currentVolume = self.coordinator?.playerService.volume ?? 1.0
        let isRestoringPlaybackSession = self.coordinator?.playerService.isRestoringPlaybackSession ?? false
        self.installUserScripts(
            on: webView.configuration.userContentController,
            isRestoringPlaybackSession: isRestoringPlaybackSession,
            targetVolume: currentVolume
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let playerService: PlayerService

        init(playerService: PlayerService) {
            self.playerService = playerService
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else { return }

            let observedVideoId = Self.observedVideoId(from: body)

            switch type {
            case "TRACK_ENDED":
                Task { @MainActor in
                    await self.playerService.handleTrackEnded(observedVideoId: observedVideoId)
                }
            case "REMOTE_NEXT":
                Task { @MainActor in
                    await self.playerService.next()
                }
            case "REMOTE_PREVIOUS":
                Task { @MainActor in
                    await self.playerService.previous()
                }
            case "AIRPLAY_STATUS":
                self.handleAirPlayStatusUpdate(body: body)
            case "LYRICS_TIME":
                self.handleLyricsTimeUpdate(body: body)
            case "PLAYBACK_AUDIO_QUALITY_STATS":
                Self.logAudioQualityStats(body: body, observedVideoId: observedVideoId)
            case "STATE_UPDATE":
                self.handleStateUpdate(body: body, observedVideoId: observedVideoId)
            default:
                return
            }
        }

        private static func observedVideoId(from body: [String: Any]) -> String? {
            guard let videoId = body["videoId"] as? String, !videoId.isEmpty else { return nil }
            return videoId
        }

        private func handleAirPlayStatusUpdate(body: [String: Any]) {
            let isConnected = body["isConnected"] as? Bool ?? false
            let wasRequested = body["wasRequested"] as? Bool ?? false

            Task { @MainActor in
                self.playerService.updateAirPlayStatus(
                    isConnected: isConnected,
                    wasRequested: wasRequested
                )
            }
        }

        private func handleLyricsTimeUpdate(body: [String: Any]) {
            guard let time = body["time"] as? Double else { return }

            Task { @MainActor in
                self.playerService.currentTimeMs = Int(time * 1000)
            }
        }

        private func handleStateUpdate(body: [String: Any], observedVideoId: String?) {
            let isPlaying = body["isPlaying"] as? Bool ?? false
            let progress = body["progress"] as? Int ?? 0
            let duration = body["duration"] as? Int ?? 0
            let title = body["title"] as? String ?? ""
            let artist = body["artist"] as? String ?? ""
            let thumbnailUrl = body["thumbnailUrl"] as? String ?? ""
            let trackChanged = body["trackChanged"] as? Bool ?? false
            let likeStatus = Self.likeStatus(from: body["likeStatus"] as? String)
            let hasVideo = body["hasVideo"] as? Bool ?? false

            Task { @MainActor in
                self.playerService.updatePlaybackState(
                    isPlaying: isPlaying,
                    progress: Double(progress),
                    duration: Double(duration)
                )

                // Update video availability.
                self.playerService.updateVideoAvailability(hasVideo: hasVideo)

                // Update like status only when track changes (initial state).
                if trackChanged {
                    self.playerService.updateLikeStatus(likeStatus)
                }

                let hasObservedMetadata = observedVideoId != nil || !title.isEmpty
                // Repeat-one still needs drift recovery, but the normal same-song polling path
                // should not rewrite `currentTrack` on every observer tick.
                let repeatOneNeedsReconcile = self.playerService.repeatMode == .one
                    && hasObservedMetadata
                    && (trackChanged
                        || (observedVideoId != nil && observedVideoId != self.playerService.currentTrack?.videoId)
                        || (observedVideoId == nil && !title.isEmpty && title != self.playerService.currentTrack?.title))
                let shouldReconcileMetadata = hasObservedMetadata && (trackChanged || repeatOneNeedsReconcile)

                if shouldReconcileMetadata {
                    self.playerService.updateTrackMetadata(
                        title: title,
                        artist: artist,
                        thumbnailUrl: thumbnailUrl,
                        videoId: observedVideoId
                    )
                }
            }
        }

        private static func likeStatus(from rawValue: String?) -> LikeStatus {
            switch rawValue {
            case "LIKE":
                .like
            case "DISLIKE":
                .dislike
            default:
                .indifferent
            }
        }

        private static let allowedAudioQualityStatsKeys: Set<String> = [
            "afmt",
            "audioBitrate",
            "audioCodec",
            "audioCodecs",
            "audioFormat",
            "audioItag",
            "audioMimeType",
            "audioQuality",
            "audio_format",
            "bitrate",
            "codec",
            "codecs",
            "debug_audioFormat",
            "debug_audioQuality",
            "debug_playbackQuality",
            "itag",
            "mimeType",
            "quality",
        ]

        private static let allowedAudioQualityStatsFragments: Set<String> = [
            "bitrate",
            "codec",
            "format",
            "itag",
            "mime",
            "quality",
        ]

        private static func logAudioQualityStats(body: [String: Any], observedVideoId: String?) {
            let message = Self.audioQualityStatsLogMessage(body: body, observedVideoId: observedVideoId)
            DiagnosticsLogger.player.info("Audio quality stats: \(message, privacy: .private)")
        }

        static func audioQualityStatsLogMessage(body: [String: Any], observedVideoId: String?) -> String {
            let preferred = Self.sanitizedLogString(body["preferred"])
            let desired = Self.sanitizedLogString(body["desired"])
            let applied = (body["applied"] as? Bool) == true ? "true" : "false"
            let observed = Self.sanitizedLogString(body["observed"])
            let source = Self.sanitizedLogString(body["source"])
            let videoId = Self.sanitizedLogString(observedVideoId, fallback: "unknown")
            let available = Self.compactJSONText(
                Self.sanitizedPrimitiveArray(body["available"]) ?? [],
                fallback: "[]"
            )
            let stats = Self.compactJSONText(Self.sanitizedStatsForNerds(body["stats"]), fallback: "{}")

            return """
            preferred=\(preferred) desired=\(desired) applied=\(applied) observed=\(observed) \
            source=\(source) videoId=\(videoId) available=\(available) stats=\(stats)
            """
        }

        private static func sanitizedLogString(_ value: Any?, fallback: String = "unknown") -> String {
            guard let value else { return fallback }

            let string: String = if let stringValue = value as? String {
                stringValue
            } else {
                String(describing: value)
            }

            let flattened = string
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\t", with: " ")

            guard !flattened.isEmpty else { return fallback }
            return String(flattened.prefix(200))
        }

        private static func compactJSONText(_ value: Any, fallback: String) -> String {
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8)
            else {
                return fallback
            }

            return text
        }

        private static func sanitizedStatsForNerds(_ value: Any?) -> [String: Any] {
            guard let value = value as? [String: Any] else { return [:] }

            var sanitized: [String: Any] = [:]
            for key in value.keys.sorted() where sanitized.count < 12 {
                guard Self.isAllowedAudioQualityStatsKey(key) else { continue }

                let sanitizedKey = String(key.prefix(80))
                if let primitive = Self.sanitizedPrimitive(value[key]) {
                    sanitized[sanitizedKey] = primitive
                    continue
                }

                if let primitiveArray = Self.sanitizedPrimitiveArray(value[key]) {
                    sanitized[sanitizedKey] = primitiveArray
                }
            }

            return sanitized
        }

        private static func isAllowedAudioQualityStatsKey(_ key: String) -> Bool {
            if self.allowedAudioQualityStatsKeys.contains(key) {
                return true
            }

            let lowercasedKey = key.lowercased()
            return lowercasedKey.contains("audio")
                && Self.allowedAudioQualityStatsFragments.contains { lowercasedKey.contains($0) }
        }

        private static func sanitizedPrimitiveArray(_ value: Any?) -> [Any]? {
            guard let values = value as? [Any] else { return nil }

            let sanitized = values.prefix(12).compactMap { Self.sanitizedPrimitive($0) }
            return sanitized.isEmpty ? nil : sanitized
        }

        private static func sanitizedPrimitive(_ value: Any?) -> Any? {
            guard let value else { return nil }

            if let value = value as? String {
                return String(value.prefix(160))
            }

            if let value = value as? Bool {
                return value
            }

            return Self.sanitizedNumericPrimitive(value)
        }

        private static func sanitizedNumericPrimitive(_ value: Any) -> Any? {
            if let value = value as? Int {
                return value
            }

            if let value = value as? Int8 {
                return value
            }

            if let value = value as? Int16 {
                return value
            }

            if let value = value as? Int32 {
                return value
            }

            if let value = value as? Int64 {
                return value
            }

            if let value = value as? UInt {
                return value
            }

            if let value = value as? UInt8 {
                return value
            }

            if let value = value as? UInt16 {
                return value
            }

            if let value = value as? UInt32 {
                return value
            }

            if let value = value as? UInt64 {
                return value
            }

            if let value = value as? Double {
                return value.isFinite ? value : nil
            }

            if let value = value as? Float {
                return value.isFinite ? Double(value) : nil
            }

            if let value = value as? NSNumber {
                return value.doubleValue.isFinite ? value : nil
            }

            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            DiagnosticsLogger.player.info(
                "Singleton WebView finished loading: \(webView.url?.absoluteString ?? "nil")"
            )

            // Apply the current volume when page finishes loading.
            // This is critical because YouTube may set its own default volume.
            let savedVolume = self.playerService.volume
            let applyVolumeScript = """
                (function() {
                    try {
                        const volume = \(savedVolume);
                        window.__kasetTargetVolume = volume;
                        window.__kasetIsSettingVolume = true;

                        const video = document.querySelector('video');
                        if (video) {
                            video.volume = volume;
                        }

                        // Sync YouTube's internal player APIs if ready.
                        const ytVolume = Math.round(volume * 100);
                        const player = document.querySelector('ytmusic-player');
                        if (player && player.playerApi && typeof player.playerApi.setVolume === 'function') {
                            player.playerApi.setVolume(ytVolume);
                        }
                        const moviePlayer = document.getElementById('movie_player');
                        if (moviePlayer && typeof moviePlayer.setVolume === 'function') {
                            moviePlayer.setVolume(ytVolume);
                        }

                        setTimeout(() => { window.__kasetIsSettingVolume = false; }, 100);
                        return video ? 'applied' : 'no-video-yet';
                    } catch (e) {
                         return 'error: ' + e;
                    }
                })();
            """
            webView.evaluateJavaScript(applyVolumeScript) { result, error in
                if let error {
                    DiagnosticsLogger.player.error(
                        "Failed to apply saved volume \(savedVolume): \(error.localizedDescription)"
                    )
                } else if let resultString = result as? String {
                    DiagnosticsLogger.player.debug("Volume apply result: \(resultString)")
                }

                // Restore lyrics high-frequency polling if it was active.
                if SingletonPlayerWebView.shared.isLyricsPollActive {
                    SingletonPlayerWebView.shared.startLyricsPoll()
                }
            }
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            // Navigation failure; logged by WebKit.
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
            // Provisional navigation failure; logged by WebKit.
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // WebView content process crashed - attempt recovery.
            DiagnosticsLogger.player.error("Singleton WebView content process terminated, attempting recovery")

            // Get the current video ID before reloading.
            let currentVideoId = SingletonPlayerWebView.shared.currentVideoId

            // Reload the WebView.
            webView.reload()

            // If we had a video playing, reload it after a brief delay.
            if let videoId = currentVideoId {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    // Reset currentVideoId to force reload.
                    SingletonPlayerWebView.shared.currentVideoId = nil
                    SingletonPlayerWebView.shared.loadVideo(videoId: videoId)
                }
            }
        }
    }
}
