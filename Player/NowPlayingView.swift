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

    let namespace: Namespace.ID
    var onDismiss: (() -> Void)?

    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            self.backgroundLayer

            VStack(spacing: 0) {
                self.topBar

                ScrollView {
                    VStack(spacing: Theme.spacingXXL) {
                        self.cassetteVisual
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

            if let artworkURL {
                ArtworkView(url: artworkURL, targetSize: .init(width: 360, height: 360), cornerRadius: 48)
                    .scaleEffect(2.35)
                    .blur(radius: 78)
                    .saturation(1.35)
                    .opacity(0.62)
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
                self.dismissNowPlaying()
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

    private var cassetteVisual: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.black.opacity(0.28))
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }

            VStack(spacing: Theme.spacingL) {
                HStack(spacing: Theme.spacingM) {
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(width: 84, height: 7)

                    Spacer()

                    ArtworkView(
                        url: self.artworkURL,
                        targetSize: .init(width: 58, height: 58),
                        cornerRadius: Theme.cornerRadiusM
                    )
                    .matchedGeometryEffect(id: "player-artwork", in: self.namespace)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cornerRadiusM, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }

                    Spacer()

                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(width: 84, height: 7)
                }

                HStack(spacing: Theme.spacingL) {
                    CassetteReelView()

                    Capsule()
                        .fill(.white.opacity(0.14))
                        .frame(width: 88, height: 22)
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        }

                    CassetteReelView()
                }

                HStack(spacing: 28) {
                    ForEach(0 ..< 4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(.white.opacity(0.12))
                            .frame(width: 34, height: 4)
                    }
                }
            }
            .padding(Theme.spacingXL)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .scaleEffect(self.playerService.state == .loading ? 0.97 : 1)
        .shadow(color: .black.opacity(0.36), radius: 34, x: 0, y: 20)
        .animation(AppAnimation.spring, value: self.playerService.state)
        .accessibilityLabel("Now playing cassette artwork")
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
        .matchedGeometryEffect(id: "player-surface", in: self.namespace)
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
}

private struct CassetteReelView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 76, height: 76)

            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 1)
                .frame(width: 76, height: 76)

            ForEach(0 ..< 6, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: 5, height: 22)
                    .offset(y: -21)
                    .rotationEffect(.degrees(Double(index) * 60))
            }

            Circle()
                .fill(.black.opacity(0.32))
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                }
        }
    }
}
