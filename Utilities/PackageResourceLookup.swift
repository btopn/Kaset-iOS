import SwiftUI

// MARK: - PackageResourceLookup

/// iOS resource lookup.
///
/// On macOS, Kaset ships resources in a nested `Kaset_Kaset.bundle` and looks
/// it up via AppKit APIs. On iOS the app bundle is flat, so resource lookup is
/// `Bundle.main` and the brand accent color is the `AccentColor` asset.
enum PackageResourceLookup {
    /// The app bundle. Localization, assets, and storyboards live here on iOS.
    static let bundle: Bundle = .main

    /// Localization bundle. Equal to `Bundle.main` on iOS.
    static let localizationBundle: Bundle? = .main

    /// The brand accent color from the asset catalog.
    static let brandAccent: Color = Color("AccentColor")
}
