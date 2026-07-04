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
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            SectionHeader(
                title: self.title,
                subtitle: self.subtitle,
                showsSeeAll: self.onSeeAll != nil,
                onSeeAll: self.onSeeAll
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.spacingS) {
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
    @Environment(\.presentNowPlaying) private var presentNowPlaying

    var body: some View {
        switch self.item {
        case .song:
            Button {
                self.playSong()
            } label: {
                self.cardContent
            }
            .buttonStyle(.interactiveCard(showShadow: false, hoverScale: 1, pressScale: 0.97))
            .contextMenu {
                self.contextMenu
            }
        case let .album(album):
            if let playlist = self.navigationPlaylist(for: album) {
                NavigationLink(value: playlist) {
                    self.cardContent
                }
                .buttonStyle(.plain)
                .contextMenu {
                    self.contextMenu
                }
            } else {
                self.cardContent
                    .contextMenu {
                        self.contextMenu
                    }
            }
        case let .playlist(playlist):
            NavigationLink(value: playlist) {
                self.cardContent
            }
            .buttonStyle(.plain)
            .contextMenu {
                self.contextMenu
            }
        case let .artist(artist):
            NavigationLink(value: artist) {
                self.cardContent
            }
            .buttonStyle(.plain)
            .contextMenu {
                self.contextMenu
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            ZStack(alignment: .topLeading) {
                ArtworkView(
                    url: self.item.thumbnailURL,
                    targetSize: .init(width: Theme.ArtworkSize.cardLarge, height: Theme.ArtworkSize.cardLarge),
                    cornerRadius: Theme.cornerRadiusL
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusL, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.24), radius: 16, x: 0, y: 10)

                if let rank {
                    Text("\(rank)")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.spacingS)
                        .padding(.vertical, Theme.spacingXS)
                        .compatGlass(tint: Theme.Colors.glassTint, in: .capsule)
                        .padding(Theme.spacingS)
                }

                if case let .song(song) = self.item {
                    Image(systemName: self.playerService.isCurrentTrack(song) && self.playerService.isPlaying ? "waveform" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .compatGlass(interactive: false, tint: Theme.Colors.glassTint, in: .circle)
                        .padding(Theme.spacingS)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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
    }

    private func playSong() {
        guard case let .song(song) = self.item else { return }
        self.presentNowPlaying()
        Task { await self.playerService.play(song: song) }
        HapticService.playback()
    }

    private func navigationPlaylist(for album: Album) -> Playlist? {
        guard album.hasNavigableId else { return nil }
        return Playlist(
            id: album.id,
            title: album.title,
            description: nil,
            thumbnailURL: album.thumbnailURL,
            trackCount: album.trackCount
        )
    }

    @ViewBuilder
    private var contextMenu: some View {
        switch self.item {
        case let .song(song):
            Button {
                self.presentNowPlaying()
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
