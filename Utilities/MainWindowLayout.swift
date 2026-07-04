import CoreGraphics

// MARK: - MainWindowLayout

/// Shared sizing constants for the app's primary surface.
///
/// On macOS this type also configures the underlying `NSWindow`'s min size and
/// autosave frame. iOS has no arbitrary window resizing, so this port keeps only
/// the sizing constants that other layout helpers (e.g. `PlayerBarLayout`)
/// reference. The window chrome is driven entirely by SwiftUI/UIScene.
enum MainWindowLayout {
    static let autosaveName = "KasetMainWindow"
    static let windowTitle = "Kaset"
    static let minimumWidth: CGFloat = 980
    static let minimumHeight: CGFloat = 600
    static let defaultWidth: CGFloat = 1100
    static let defaultHeight: CGFloat = 760
}
