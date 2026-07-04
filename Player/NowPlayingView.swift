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
        ZStack(alignment: .top) {
            // Ambient backdrop derived from artwork (subtle tint).
            if let url = self.playerService.currentTrack?.thumbnailURL {
                ArtworkView(url: url, targetSize: .init(width: 60, height: 60), cornerRadius: 0)
                    .blur(radius: 60)
                    .opacity(0.5)
                    .ignoresSafeArea()
            } else {
                Color(.systemBackground).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                self.grabber

                ScrollView {
                    VStack(spacing: Theme.spacingXL) {
                        self.artworkOrVideo
                        self.trackInfo
                        ScrubBar(showsTimes: true)
                        PlayerControls(size: .large)
                        self.auxiliaryButtons
                    }
                    .padding(.horizontal, Theme.spacingXL)
                    .padding(.top, Theme.spacingL)
                    .padding(.bottom, Theme.spacingXXXL)
                }
            }
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
        .sheet(isPresented: self.$showQueue) {
            QueueView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: self.$showLyrics) {
            LyricsView()
                .presentationDetents([.medium, .large])
        }
    }

    private var grabber: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
            Spacer()
        }
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
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
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
                .font(.title2.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(self.playerService.currentTrack?.artistsDisplay ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var auxiliaryButtons: some View {
        HStack(spacing: Theme.spacingXXXL) {
            Button {
                self.showLyrics = true
            } label: {
                Image(systemName: "text.quote")
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Button {
                self.playerService.showAirPlayPicker()
                HapticService.toggle()
            } label: {
                Image(systemName: "airplayaudio")
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Button {
                self.showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Theme.spacingS)
    }
}
