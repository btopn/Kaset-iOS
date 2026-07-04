import SwiftUI

// MARK: - NowPlayingView

/// Full-screen now-playing surface.
///
/// Shows the current track's artwork, which can swap to the in-app music
/// video (locked to the song — no YouTube source toggle) when available.
/// Reuses `ScrubBar`, `PlayerControls`, and `ArtworkView` from the design
/// system. Hosts the hidden playback `PlayerWebView` so DRM audio/video keeps
/// playing while this view is shown.
struct NowPlayingView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(\.dismiss) private var dismiss
    @Environment(WebKitManager.self) private var webKitManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openArtistPage) private var openArtistPage
    @Environment(\.client) private var client
    @Environment(SyncedLyricsService.self) private var lyricsService

    let namespace: Namespace.ID
    var onDismiss: (() -> Void)?

    private enum NowPlayingMode: String {
        case player
        case lyrics
        case queue
    }

    @State private var mode: NowPlayingMode = .player
    @State private var dragOffset: CGFloat = 0
    @State private var isOpeningArtist = false
    @State private var palette: ColorExtractor.ColorPalette = .default
    @State private var paletteArtworkURL: URL?

    var body: some View {
        GeometryReader { proxy in
            let panelHeight = self.panelHeight(in: proxy.size)

            ZStack(alignment: .bottom) {
                Color.black.opacity(self.colorScheme == .dark ? 0.28 : 0.08)
                    .ignoresSafeArea()

                ZStack(alignment: .top) {
                    self.backgroundLayer

                    VStack(spacing: Theme.spacingS) {
                        VStack(spacing: Theme.spacingS) {
                            self.albumArtwork(size: self.artworkSize(width: proxy.size.width, panelHeight: panelHeight))
                            self.trackInfo
                        }

                        self.modeContent

                        self.auxiliaryButtons
                    }
                    .padding(.horizontal, Theme.spacingL)
                    .padding(.top, Theme.spacingM)
                    .padding(.bottom, Theme.spacingL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(width: proxy.size.width, height: panelHeight)
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .shadow(color: .black.opacity(self.colorScheme == .dark ? 0.34 : 0.16), radius: 28, x: 0, y: -8)
                .offset(y: max(0, self.dragOffset))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard value.translation.height > 0 else { return }
                    self.dragOffset = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 120 || value.predictedEndTranslation.height > 240 {
                        self.dismissNowPlaying()
                    } else {
                        withAnimation(AppAnimation.spring) {
                            self.dragOffset = 0
                        }
                    }
                }
        )
        .foregroundStyle(.primary)
        .task(id: self.artworkURL) {
            await self.updatePalette()
        }
        .task(id: self.lyricsTaskID) {
            await self.fetchLyricsIfNeeded()
        }
        .onChange(of: self.mode) { _, newValue in
            self.syncLyricsPolling(for: newValue)
        }
        .onChange(of: self.lyricsService.currentLyrics) { _, _ in
            self.syncLyricsPolling(for: self.mode)
        }
        .onDisappear {
            SingletonPlayerWebView.shared.stopLyricsPoll()
        }
        // The hidden WebView keeps DRM audio playing through this view's lifetime.
        .background(
            Group {
                if let videoId = self.playerService.pendingPlayVideoId ?? self.playerService.currentTrack?.videoId {
                    PlayerWebView(videoId: videoId)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                }
            }
            .allowsHitTesting(false)
        )
    }

    private var backgroundLayer: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                if let artworkURL {
                    CachedAsyncImage(
                        url: artworkURL,
                        targetSize: .init(width: proxy.size.width, height: proxy.size.height)
                    ) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        self.palette.primary
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .saturation(1.15)
                    .opacity(self.colorScheme == .dark ? 0.46 : 0.34)
                    .ignoresSafeArea()
                }

                Rectangle()
                    .fill(self.albumArtworkWash)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: self.backdropGradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }

    private func albumArtwork(size: CGFloat) -> some View {
        ArtworkView(
            url: self.artworkURL,
            targetSize: .init(width: size, height: size),
            cornerRadius: 26
        )
        .matchedGeometryEffect(id: "player-artwork", in: self.namespace)
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(self.colorScheme == .dark ? 0.38 : 0.16), radius: 32, x: 0, y: 20)
        .scaleEffect(self.playerService.state == .loading ? 0.97 : 1)
        .animation(AppAnimation.spring, value: self.playerService.state)
        .accessibilityLabel("Now playing artwork")
    }

    private var trackInfo: some View {
        VStack(spacing: Theme.spacingXS) {
            Text(self.playerService.currentTrack?.title ?? "")
                .font(.title2.weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let artist = self.displayArtist {
                Button {
                    self.openArtist(artist)
                } label: {
                    Text(self.playerService.currentTrack?.artistsDisplay ?? "")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.accent)
                        .lineLimit(1)
                        .padding(.horizontal, Theme.spacingM)
                        .padding(.vertical, Theme.spacingXS)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(self.isOpeningArtist)
                .accessibilityAddTraits(.isLink)
            } else {
                Text(self.playerService.currentTrack?.artistsDisplay ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.accent)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var modeContent: some View {
        switch self.mode {
        case .player:
            self.transportPanel
        case .lyrics:
            self.lyricsPanel
        case .queue:
            self.queuePanel
        }
    }

    private var transportPanel: some View {
        VStack(spacing: Theme.spacingS) {
            ScrubBar(showsTimes: true)
            PlayerControls(size: .large)
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.vertical, Theme.spacingM)
        .frame(maxWidth: 360, minHeight: 132, maxHeight: 132)
        .compatGlass(interactive: false, tint: Theme.Colors.glassTint, in: .rect(cornerRadius: 30))
        .matchedGeometryEffect(id: "player-surface", in: self.namespace)
    }

    private var auxiliaryButtons: some View {
        HStack(spacing: Theme.spacingM) {
            self.iconButton(systemName: "text.quote", accessibilityLabel: "Lyrics", isSelected: self.mode == .lyrics) {
                self.setMode(self.mode == .lyrics ? .player : .lyrics)
            }

            self.iconButton(systemName: "airplayaudio", accessibilityLabel: "AirPlay") {
                self.playerService.showAirPlayPicker()
                HapticService.toggle()
            }

            self.iconButton(
                systemName: self.playerService.currentTrackInLibrary ? "checkmark.circle.fill" : "plus.circle",
                accessibilityLabel: self.playerService.currentTrackInLibrary ? "Remove from Library" : "Add to Library"
            ) {
                self.playerService.toggleLibraryStatus()
                HapticService.toggle()
            }

            self.iconButton(systemName: "list.bullet", accessibilityLabel: "Up Next", isSelected: self.mode == .queue) {
                self.setMode(self.mode == .queue ? .player : .queue)
            }
        }
    }

    private func iconButton(
        systemName: String,
        accessibilityLabel: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.Colors.accent : .primary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .compatGlass(interactive: true, tint: Theme.Colors.glassTint, in: Circle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var lyricsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingM) {
                if self.lyricsService.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.spacingXL)
                } else {
                    switch self.lyricsService.currentLyrics {
                    case .unavailable:
                        EmptyStateView(
                            title: "No Lyrics",
                            message: "Lyrics aren't available for this track.",
                            systemImage: "text.quote"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.spacingXL)
                    case let .plain(lyrics):
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    case let .synced(synced):
                        let statuses = synced.lineStatuses(at: self.playerService.currentTimeMs)
                        ForEach(Array(synced.lines.enumerated()), id: \.element.id) { index, line in
                            Text(self.displayText(for: line))
                                .font(statuses[safe: index] == .current ? .body.weight(.bold) : .body.weight(.medium))
                                .foregroundStyle(statuses[safe: index] == .current ? Theme.Colors.accent : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(Theme.spacingL)
        }
        .frame(maxWidth: 360, minHeight: 156, maxHeight: 210)
        .compatGlass(interactive: false, tint: Theme.Colors.glassTint, in: .rect(cornerRadius: 30))
    }

    private var queuePanel: some View {
        ScrollView {
            LazyVStack(spacing: Theme.spacingS) {
                if self.queueItems.isEmpty {
                    if let currentTrack = self.playerService.currentTrack {
                        self.currentOnlyQueueRow(currentTrack)
                        Text("No upcoming tracks")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Theme.spacingS)
                    } else {
                        EmptyStateView(
                            title: "Queue is Empty",
                            message: "Play something to build a queue.",
                            systemImage: "list.bullet"
                        )
                        .padding(.top, Theme.spacingXL)
                    }
                } else {
                    ForEach(self.queueItems) { item in
                        self.queueRow(item)
                    }
                }
            }
            .padding(Theme.spacingM)
        }
        .frame(maxWidth: 360, minHeight: 156, maxHeight: 210)
        .compatGlass(interactive: false, tint: Theme.Colors.glassTint, in: .rect(cornerRadius: 30))
    }

    private func currentOnlyQueueRow(_ song: Song) -> some View {
        HStack(spacing: Theme.spacingS) {
            ArtworkView(
                url: song.displayThumbnailURL,
                targetSize: .init(width: 42, height: 42),
                cornerRadius: 9
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(song.artistsDisplay)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.spacingS)

            Image(systemName: "speaker.wave.2.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.Colors.accent)
        }
        .padding(.horizontal, Theme.spacingS)
        .padding(.vertical, 6)
        .background(Theme.Colors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func queueRow(_ item: NowPlayingQueueItem) -> some View {
        let isCurrent = item.index == self.playerService.currentIndex

        return Button {
            Task { await self.playerService.playFromQueue(at: item.index) }
            HapticService.playback()
        } label: {
            HStack(spacing: Theme.spacingS) {
                ArtworkView(
                    url: item.entry.song.displayThumbnailURL,
                    targetSize: .init(width: 42, height: 42),
                    cornerRadius: 9
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.entry.song.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(item.entry.song.artistsDisplay)
                        .font(.caption)
                        .foregroundStyle(isCurrent ? Theme.Colors.accent : .secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Theme.spacingS)

                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(.horizontal, Theme.spacingS)
            .padding(.vertical, 6)
            .background(isCurrent ? Theme.Colors.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func dismissNowPlaying() {
        if let onDismiss {
            onDismiss()
        } else {
            self.dismiss()
        }
    }

    private var artworkURL: URL? {
        self.playerService.currentTrack?.displayThumbnailURL
    }

    private var queueItems: [NowPlayingQueueItem] {
        self.playerService.queueEntries.enumerated().map { index, entry in
            NowPlayingQueueItem(index: index, entry: entry)
        }
    }

    private var lyricsTaskID: String {
        "\(self.mode.rawValue)-\(self.currentTrackId)"
    }

    private var currentTrackId: String {
        self.playerService.currentTrack?.videoId ?? ""
    }

    private var navigableArtist: Artist? {
        self.playerService.currentTrack?.artists.first(where: \.hasNavigableId)
    }

    private var displayArtist: Artist? {
        self.navigableArtist ?? self.playerService.currentTrack?.artists.first
    }

    private func openArtist(_ artist: Artist) {
        if artist.hasNavigableId {
            self.openArtistPage(artist)
            return
        }

        guard let client else { return }
        self.isOpeningArtist = true
        Task {
            defer { self.isOpeningArtist = false }
            let response = try? await client.searchArtists(query: artist.name)
            guard let resolvedArtist = response?.artists.first(where: \.hasNavigableId) else {
                return
            }

            self.openArtistPage(resolvedArtist)
        }
    }

    private var backdropGradientColors: [Color] {
        if self.colorScheme == .dark {
            return [
                self.palette.primary.opacity(0.82),
                self.palette.secondary.opacity(0.88),
                Theme.Colors.background.opacity(0.96),
            ]
        }

        return [
            self.palette.lightTint.opacity(0.72),
            Theme.Colors.background.opacity(0.9),
            Theme.Colors.background,
        ]
    }

    private var albumArtworkWash: Color {
        self.colorScheme == .dark
            ? .black.opacity(0.42)
            : .white.opacity(0.62)
    }

    private func artworkSize(width: CGFloat, panelHeight: CGFloat) -> CGFloat {
        min(width - Theme.spacingXL * 2, panelHeight * 0.36, 318)
    }

    private func panelHeight(in size: CGSize) -> CGFloat {
        min(size.height * 0.9, size.height - 18)
    }

    private func setMode(_ mode: NowPlayingMode) {
        withAnimation(AppAnimation.spring) {
            self.mode = mode
        }
    }

    private func updatePalette() async {
        guard let artworkURL else {
            self.paletteArtworkURL = nil
            self.palette = .default
            return
        }

        let sourceURL = artworkURL
        let targetSize = CGSize(width: 96, height: 96)
        let nextPalette: ColorExtractor.ColorPalette
        if let image = await ImageCache.shared.image(for: sourceURL, targetSize: targetSize) {
            nextPalette = ColorExtractor.extractPalette(from: image)
        } else {
            nextPalette = .default
        }

        guard self.artworkURL == sourceURL else { return }
        withAnimation(AppAnimation.snappy) {
            self.paletteArtworkURL = sourceURL
            self.palette = nextPalette
        }
    }

    private func fetchLyricsIfNeeded() async {
        guard self.mode == .lyrics, let track = self.playerService.currentTrack else { return }
        let info = LyricsSearchInfo(
            title: track.title,
            artist: track.artistsDisplay,
            album: track.album?.title,
            duration: track.duration,
            videoId: track.videoId
        )
        await self.lyricsService.fetchLyrics(for: info)
        self.syncLyricsPolling(for: self.mode)
    }

    private func syncLyricsPolling(for mode: NowPlayingMode) {
        if mode == .lyrics, case .synced = self.lyricsService.currentLyrics {
            SingletonPlayerWebView.shared.startLyricsPoll()
        } else {
            SingletonPlayerWebView.shared.stopLyricsPoll()
        }
    }

    private func displayText(for line: SyncedLyricLine) -> String {
        guard let romanizedText = line.romanizedText, !romanizedText.isEmpty else {
            return line.text.isEmpty ? " " : line.text
        }
        return line.text.isEmpty ? romanizedText : "\(line.text)\n\(romanizedText)"
    }
}

private struct NowPlayingQueueItem: Identifiable {
    let index: Int
    let entry: QueueEntry

    var id: UUID {
        self.entry.id
    }
}
