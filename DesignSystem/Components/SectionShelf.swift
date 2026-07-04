import SwiftUI

// MARK: - SectionShelf

/// The one horizontal card shelf used by Home, Explore, Charts, New Releases,
/// and Moods.
///
/// Renders a `SectionHeader` followed by a horizontally scrolling row of
/// `SectionCard`s for the given items. Features feed it `[HomeSectionItem]`
/// (or typed albums/playlists/artists) plus tap/context handlers — they never
/// rebuild the carousel themselves.
struct SectionShelf<Header: View>: View {
    let title: String
    var subtitle: String? = nil
    var onSeeAll: (() -> Void)? = nil
    let items: [HomeSectionItem]
    var isChart: Bool = false
    @ViewBuilder var customHeader: Header

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            SectionHeader(
                title: self.title,
                subtitle: self.subtitle,
                showsSeeAll: self.onSeeAll != nil,
                onSeeAll: self.onSeeAll
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.spacingM) {
                    ForEach(Array(self.items.enumerated()), id: \.element.id) { index, item in
                        SectionCard(item: item, rank: self.isChart ? index + 1 : nil)
                            .padding(.leading, index == 0 ? Theme.spacingXL : 0)
                            .padding(.trailing, index == self.items.count - 1 ? Theme.spacingXL : 0)
                    }
                }
            }
        }
    }
}

extension SectionShelf where Header == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        onSeeAll: (() -> Void)? = nil,
        items: [HomeSectionItem],
        isChart: Bool = false
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            onSeeAll: onSeeAll,
            items: items,
            isChart: isChart
        ) {
            EmptyView()
        }
    }
}

// MARK: - SectionCard

/// A single card in a `SectionShelf`. Renders artwork + title + subtitle for
/// any `HomeSectionItem` and routes taps through the centralized callbacks.
struct SectionCard: View {
    let item: HomeSectionItem
    var rank: Int? = nil

    @Environment(PlayerService.self) private var playerService
    @Environment(\.client) private var client

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            ZStack(alignment: .topLeading) {
                ArtworkView(
                    url: self.item.thumbnailURL,
                    targetSize: .init(width: Theme.ArtworkSize.cardLarge, height: Theme.ArtworkSize.cardLarge),
                    cornerRadius: Theme.cornerRadiusL
                )

                if let rank {
                    Text("\(rank)")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.spacingS)
                        .padding(.vertical, Theme.spacingXS)
                        .background(.ultraThinMaterial, in: .capsule)
                        .padding(Theme.spacingS)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(self.item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let subtitle = self.item.subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(width: Theme.ArtworkSize.cardLarge, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            self.handleTap()
        }
        .contextMenu {
            self.contextMenu
        }
    }

    private func handleTap() {
        switch self.item {
        case let .song(song):
            Task { await self.playerService.play(song: song) }
            HapticService.playback()
        case let .album(album):
            // Navigate via the album's underlying playlist representation.
            NavigationBus.shared.openAlbum(album)
        case let .playlist(playlist):
            NavigationBus.shared.openPlaylist(playlist)
        case let .artist(artist):
            NavigationBus.shared.openArtist(artist)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        switch self.item {
        case let .song(song):
            Button {
                Task { await self.playerService.play(song: song) }
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            ShareContextMenu.menuItem(for: song)
        case let .album(album):
            ShareContextMenu.menuItem(for: album)
        case let .playlist(playlist):
            ShareContextMenu.menuItem(for: playlist)
        case let .artist(artist):
            ShareContextMenu.menuItem(for: artist)
        }
    }
}

// MARK: - NavigationBus

/// A lightweight, centralized navigation bus for card taps that need to push a
/// destination onto whichever tab's `NavigationStack` is active.
///
/// Each tab's root view registers its `NavigationPath` here on appear; card
/// components call `NavigationBus.shared.openPlaylist(...)` etc. without
/// needing a path passed down.
@MainActor
final class NavigationBus: ObservableObject {
    static let shared = NavigationBus()

    /// Generic navigation destinations pushed onto the active path.
    enum Destination: Equatable {
        case playlist(Playlist)
        case artist(Artist)
        case album(Album)
        case mood(MoodCategory)
    }

    @Published private(set) var pendingDestination: Destination?

    private init() {}

    func openPlaylist(_ playlist: Playlist) {
        self.pendingDestination = .playlist(playlist)
    }

    func openArtist(_ artist: Artist) {
        self.pendingDestination = .artist(artist)
    }

    func openAlbum(_ album: Album) {
        // Albums navigate as a playlist with an album-prefix ID when navigable.
        if album.hasNavigableId {
            self.pendingDestination = .playlist(Playlist(
                id: album.id,
                title: album.title,
                description: nil,
                thumbnailURL: album.thumbnailURL,
                trackCount: album.trackCount
            ))
        }
    }

    func openMood(_ mood: MoodCategory) {
        self.pendingDestination = .mood(mood)
    }

    /// Consumes the pending destination so a host can append it once.
    func consume() -> Destination? {
        let value = self.pendingDestination
        self.pendingDestination = nil
        return value
    }
}
