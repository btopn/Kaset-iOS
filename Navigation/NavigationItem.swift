import Foundation

// MARK: - NavigationItem

/// Top-level navigation destinations.
///
/// On macOS this drives the sidebar; on iOS it drives the tab bar plus pushed
/// destinations. `SettingsManager` references it for launch-page mapping, so
/// the cases mirror Kaset's macOS enum.
enum NavigationItem: String, Hashable, CaseIterable, Identifiable {
    case home = "Home"
    case explore = "Explore"
    case search = "Search"
    case charts = "Charts"
    case moodsAndGenres = "Moods & Genres"
    case newReleases = "New Releases"
    case likedMusic = "Liked Music"
    case library = "Library"
    case history = "History"

    var id: String {
        self.rawValue
    }

    var displayName: String {
        switch self {
        case .home: String(localized: "Home")
        case .explore: String(localized: "Explore")
        case .search: String(localized: "Search")
        case .charts: String(localized: "Charts")
        case .moodsAndGenres: String(localized: "Moods & Genres")
        case .newReleases: String(localized: "New Releases")
        case .likedMusic: String(localized: "Liked Music")
        case .library: String(localized: "Library")
        case .history: String(localized: "History")
        }
    }

    /// SF Symbol for tab/row iconography.
    var icon: String {
        switch self {
        case .home: "play.house"
        case .explore: "safari"
        case .search: "magnifyingglass"
        case .charts: "chart.bar"
        case .moodsAndGenres: "theatermasks"
        case .newReleases: "sparkles"
        case .likedMusic: "heart.fill"
        case .library: "books.vertical"
        case .history: "clock.arrow.circlepath"
        }
    }
}
