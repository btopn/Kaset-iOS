import Foundation

// MARK: - HomeSection

/// Represents a section on the YouTube Music home page.
struct HomeSection: Identifiable {
    let id: String
    let title: String
    let items: [HomeSectionItem]
    /// Whether this section is a chart (e.g., "Top 100", "Trending", "Charts").
    /// Chart sections are rendered as vertical numbered lists instead of horizontal carousels.
    let isChart: Bool

    init(id: String, title: String, items: [HomeSectionItem], isChart: Bool = false) {
        self.id = id
        self.title = title
        self.items = items
        self.isChart = isChart
    }
}

// MARK: - HomeSectionItem

/// An item within a home section (can be song, album, playlist, or artist).
enum HomeSectionItem: Identifiable {
    case song(Song)
    case album(Album)
    case playlist(Playlist)
    case artist(Artist)

    var id: String {
        switch self {
        case let .song(song):
            "song-\(song.id)"
        case let .album(album):
            "album-\(album.id)"
        case let .playlist(playlist):
            "playlist-\(playlist.id)"
        case let .artist(artist):
            "artist-\(artist.id)"
        }
    }

    var title: String {
        switch self {
        case let .song(song):
            song.title
        case let .album(album):
            album.title
        case let .playlist(playlist):
            playlist.title
        case let .artist(artist):
            artist.name
        }
    }

    var subtitle: String? {
        switch self {
        case let .song(song):
            song.artistsDisplay
        case let .album(album):
            album.artistsDisplay
        case let .playlist(playlist):
            playlist.author?.name
        case .artist:
            "Artist"
        }
    }

    var homeCardSubtitle: String? {
        guard let subtitle else { return nil }
        return Self.cleanedHomeCardSubtitle(subtitle)
    }

    private static func subtitleComponents(_ subtitle: String) -> [String] {
        subtitle
            .replacingOccurrences(of: " • ", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func cleanedHomeCardSubtitle(_ subtitle: String) -> String? {
        var components = Self.subtitleComponents(subtitle)

        while let first = components.first, Self.isLeadingMetadataLabel(first) {
            components.removeFirst()
        }

        guard !components.isEmpty else { return nil }

        if components.count > 1,
           let count = components.last,
           Self.isCountMetadata(count)
        {
            let name = components.dropLast().joined(separator: ", ")
            return "\(name) · \(count)"
        }

        let result = components.joined(separator: ", ")
        return result.isEmpty ? nil : result
    }

    private static func isLeadingMetadataLabel(_ value: String) -> Bool {
        switch value.lowercased() {
        case "album", "artist", "song", "single", "ep", "playlist", "podcast", "episode", "video":
            true
        default:
            false
        }
    }

    private static func isCountMetadata(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        let hasNumber = lowercased.rangeOfCharacter(from: .decimalDigits) != nil
        return lowercased.contains("views")
            || (hasNumber && lowercased.contains("song"))
            || (hasNumber && lowercased.contains("track"))
            || (hasNumber && lowercased.contains("album"))
            || (hasNumber && lowercased.contains("subscriber"))
    }

    var thumbnailURL: URL? {
        switch self {
        case let .song(song):
            song.displayThumbnailURL
        case let .album(album):
            album.thumbnailURL
        case let .playlist(playlist):
            playlist.thumbnailURL
        case let .artist(artist):
            artist.thumbnailURL
        }
    }

    /// Returns the video ID if this item is playable.
    var videoId: String? {
        switch self {
        case let .song(song):
            song.videoId
        default:
            nil
        }
    }

    /// Returns the browse ID for navigation (playlists, albums, artists).
    var browseId: String? {
        switch self {
        case .song:
            nil
        case let .album(album):
            album.id
        case let .playlist(playlist):
            playlist.id
        case let .artist(artist):
            artist.id
        }
    }

    /// Returns the underlying playlist if this is a playlist item.
    var playlist: Playlist? {
        if case let .playlist(playlist) = self {
            return playlist
        }
        return nil
    }

    /// Returns the underlying album if this is an album item.
    var album: Album? {
        if case let .album(album) = self {
            return album
        }
        return nil
    }
}
