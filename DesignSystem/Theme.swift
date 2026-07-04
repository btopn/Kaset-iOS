import SwiftUI

// MARK: - Theme

/// Centralized design tokens for the app.
///
/// One source of truth for spacing, corner radii, and layout constants so
/// every feature sizes itself consistently. Colors come from the asset
/// catalog (`AccentColor`) and system semantic colors.
enum Theme {
    // MARK: - Colors

    enum Colors {
        static let background = Color(red: 0.08, green: 0.08, blue: 0.08)
        static let surfaceStrong = Color.white.opacity(0.14)
        static let glassTint = Color.white.opacity(0.16)
        static let accent = Color(red: 1.0, green: 0.06, blue: 0.32)
    }

    // MARK: - Spacing

    /// 4pt
    static let spacingXS: CGFloat = 4
    /// 8pt
    static let spacingS: CGFloat = 8
    /// 12pt
    static let spacingM: CGFloat = 12
    /// 16pt
    static let spacingL: CGFloat = 16
    /// 20pt
    static let spacingXL: CGFloat = 20
    /// 24pt
    static let spacingXXL: CGFloat = 24
    /// 32pt
    static let spacingXXXL: CGFloat = 32

    // MARK: - Corner Radii

    static let cornerRadiusS: CGFloat = 8
    static let cornerRadiusM: CGFloat = 12
    static let cornerRadiusL: CGFloat = 16
    static let cornerRadiusXL: CGFloat = 22

    // MARK: - Artwork

    /// Square artwork sizes used across cards, rows, and the now-playing screen.
    enum ArtworkSize {
        static let row: CGFloat = 48
        static let cardSmall: CGFloat = 140
        static let cardLarge: CGFloat = 180
        static let nowPlaying: CGFloat = 320
    }
}
