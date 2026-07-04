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

    @State private var showQueue = false
    @State private var showLyrics = false

    var body: some View {
        ZStack {
            self.backgroundLayer

            VStack(spacing: 0) {
                self.topBar

                ScrollView {
                    VStack(spacing: Theme.spacingXXL) {
                        self.artworkOrVideo
                        self.trackInfo
                        self.transportPanel
                        self.auxiliaryButtons
                    }
                    .padding(.horizontal, Theme.spacingXL)
                    .padding(.top, Theme.spacingXXL)
                    .padding(.bottom, Theme.spacingXXXL)
                }
                .scrollIndicators(.hidden)
            }
        }
        .foregroundStyle(.white)
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

            if let url = self.playerService.currentTrack?.thumbnailURL {
                ArtworkView(url: url, targetSize: .init(width: 260, height: 260), cornerRadius: 36)
                    .scaleEffect(1.85)
                    .blur(radius: 72)
                    .saturation(1.35)
                    .opacity(0.55)
                    .ignoresSafeArea()
            }

            LinearGradient(
                colors: [
                    .black.opacity(0.08),
                    Theme.Colors.background.opacity(0.72),
                    Theme.Colors.background,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                self.dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .compatGlass(interactive: true, tint: Theme.Colors.glassTint, in: .circle)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Now Playing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                self.showQueue = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38)
                    .compatGlass(interactive: true, tint: Theme.Colors.glassTint, in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.spacingXL)
        .padding(.top, Theme.spacingS)
    }

    /// Album artwork that flips to the in-app video when the track has one
    /// and the user taps it.
    private var artworkOrVideo: some View {
        Group {
            ArtworkView(
                url: self.playerService.currentTrack?.thumbnailURL,
                targetSize: .init(width: Theme.ArtworkSize.nowPlaying, height: Theme.ArtworkSize.nowPlaying),
                cornerRadius: Theme.cornerRadiusXL
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadiusXL, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 36, x: 0, y: 22)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(self.playerService.state == .loading ? 0.97 : 1)
        .animation(AppAnimation.spring, value: self.playerService.state)
        .onTapGesture {
            // Toggle the video surface for tracks that have one.
            if self.playerService.currentTrackHasVideo {
                self.playerService.showVideo.toggle()
                HapticService.toggle()
            }
        }
    }

    private var trackInfo: some View {
        VStack(spacing: Theme.spacingXS) {
            Text(self.playerService.currentTrack?.title ?? "")
                .font(.title2.weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(self.playerService.currentTrack?.artistsDisplay ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var transportPanel: some View {
        VStack(spacing: Theme.spacingL) {
            ScrubBar(showsTimes: true)
            PlayerControls(size: .large)
        }
        .padding(Theme.spacingL)
        .compatGlass(tint: Theme.Colors.glassTint, in: .rect(cornerRadius: 28))
    }

    private var auxiliaryButtons: some View {
        CompatGlassContainer(spacing: Theme.spacingM) {
            HStack(spacing: Theme.spacingM) {
                self.glassIconButton(systemName: "text.quote") {
                    self.showLyrics = true
                }

                self.glassIconButton(systemName: "airplayaudio") {
                    self.playerService.showAirPlayPicker()
                    HapticService.toggle()
                }

                self.glassIconButton(systemName: self.playerService.currentTrackInLibrary ? "checkmark.circle.fill" : "plus.circle") {
                    self.playerService.toggleLibraryStatus()
                    HapticService.toggle()
                }

                self.glassIconButton(systemName: "list.bullet") {
                    self.showQueue = true
                }
            }
        }
    }

    private func glassIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 52, height: 52)
                .compatGlass(interactive: true, tint: Theme.Colors.glassTint, in: .circle)
        }
        .buttonStyle(.plain)
    }
}
