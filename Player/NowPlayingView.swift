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

    let namespace: Namespace.ID
    var onDismiss: (() -> Void)?

    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var dragOffset: CGFloat = 0
    @State private var isOpeningArtist = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                self.backgroundLayer

                VStack(spacing: Theme.spacingM) {
                    self.topBar

                    Spacer(minLength: 0)
                    self.albumArtwork(size: self.artworkSize(in: proxy.size))
                    self.trackInfo
                    self.transportPanel
                    self.auxiliaryButtons
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Theme.spacingL)
                .padding(.top, Theme.spacingS)
                .padding(.bottom, Theme.spacingL)
            }
        }
        .offset(y: max(0, self.dragOffset))
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
        .sheet(isPresented: self.$showQueue) {
            QueueView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: self.$showLyrics) {
            LyricsView()
                .presentationDetents([.medium, .large])
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            if let artworkURL {
                ArtworkView(url: artworkURL, targetSize: .init(width: 420, height: 420), cornerRadius: 52)
                    .scaleEffect(2.6)
                    .blur(radius: 82)
                    .saturation(1.45)
                    .opacity(self.colorScheme == .dark ? 0.64 : 0.36)
                    .ignoresSafeArea()
            }

            LinearGradient(
                colors: self.backdropGradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                self.dismissNowPlaying()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .compatGlass(interactive: true, tint: Theme.Colors.glassTint, in: Circle())

            Spacer()

            Text("Now Playing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Menu {
                if let song = self.playerService.currentTrack {
                    ShareContextMenu.menuItem(for: song)
                }

                Button {
                    self.playerService.toggleLibraryStatus()
                    HapticService.toggle()
                } label: {
                    Label(
                        self.playerService.currentTrackInLibrary ? "Remove from Library" : "Add to Library",
                        systemImage: self.playerService.currentTrackInLibrary ? "checkmark.circle.fill" : "plus.circle"
                    )
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .compatGlass(interactive: true, tint: Theme.Colors.glassTint, in: Circle())
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
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var transportPanel: some View {
        VStack(spacing: Theme.spacingM) {
            ScrubBar(showsTimes: true)
            PlayerControls(size: .large)
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.vertical, Theme.spacingM)
        .frame(maxWidth: 360)
        .compatGlass(interactive: false, tint: Theme.Colors.glassTint, in: .rect(cornerRadius: 30))
        .matchedGeometryEffect(id: "player-surface", in: self.namespace)
    }

    private var auxiliaryButtons: some View {
        HStack(spacing: Theme.spacingM) {
            self.iconButton(systemName: "text.quote", accessibilityLabel: "Lyrics") {
                self.showLyrics = true
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

            self.iconButton(systemName: "list.bullet", accessibilityLabel: "Up Next") {
                self.showQueue = true
            }
        }
    }

    private func iconButton(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .compatGlass(interactive: true, tint: Theme.Colors.glassTint, in: Circle())
        .accessibilityLabel(accessibilityLabel)
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
                .black.opacity(0.12),
                Theme.Colors.background.opacity(0.72),
                Theme.Colors.background,
            ]
        }

        return [
            .white.opacity(0.24),
            Theme.Colors.background.opacity(0.84),
            Theme.Colors.background,
        ]
    }

    private func artworkSize(in size: CGSize) -> CGFloat {
        min(size.width - Theme.spacingL * 2, size.height * 0.52, 348)
    }
}
