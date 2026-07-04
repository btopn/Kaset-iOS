import AVFoundation
import UIKit

/// Manages iOS lifecycle: background audio session and remote command routing.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.configureAudioSession()
        return true
    }

    /// Configures a playback-category audio session so DRM audio from the hidden
    /// WKWebView continues in the background and routes through AirPlay.
    static func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal: playback will still work while foregrounded.
            print("Failed to configure audio session: \(error)")
        }
    }
}
