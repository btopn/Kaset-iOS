import SwiftUI

/// Entry point for Kaset on iOS.
@main
struct KasetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
