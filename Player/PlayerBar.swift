import SwiftUI

// MARK: - PlayerBar

/// Compact player bar pinned above the tab bar.
///
/// Shows current artwork, title, artist, a play/pause, and a seek hint.
/// Tapping the bar expands the full `NowPlayingView`. Hosts the hidden
/// playback WebView when a track is pending. Reuses `PlayerControls` (compact)
/// and `ArtworkView` from the design system — no bespoke controls here.
struct PlayerBar: View {
    @Environment(PlayerService.self) private var playerService
    @Binding var isNowPlayingPresented: Bool
    let namespace: Namespace.ID

    var body: some View {
        if self.playerService.currentTrack != nil || self.playerService.pendingPlayVideoId != nil {
            self.content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.spacingXS) {
                HStack(spacing: Theme.spacingM) {
                    ArtworkView(
                        url: self.artworkURL,
                        targetSize: .init(width: 42, height: 42),
                        cornerRadius: 10
                    )
                    .matchedGeometryEffect(id: "player-artwork", in: self.namespace, isSource: !self.isNowPlayingPresented)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(self.playerService.currentTrack?.title ?? "Loading...")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(self.playerService.currentTrack?.artistsDisplay ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Theme.spacingS)

                    self.playPauseButton
                    self.nextButton
                }

                self.progressLine
            }
            .padding(.horizontal, Theme.spacingM)
            .padding(.vertical, 10)
            .compatGlass(interactive: true, tint: Theme.Colors.glassTint, in: .rect(cornerRadius: 28))
            .matchedGeometryEffect(id: "player-surface", in: self.namespace, isSource: !self.isNowPlayingPresented)
            .shadow(color: .black.opacity(0.36), radius: 22, x: 0, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .onTapGesture {
                self.openNowPlaying()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(self.accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                self.openNowPlaying()
            }
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.bottom, Theme.spacingS)
    }

    private var playPauseButton: some View {
        Button {
            Task { await self.playerService.playPause() }
            HapticService.playback()
        } label: {
            Image(systemName: self.playerService.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .compatGlass(interactive: true, tint: Theme.Colors.surfaceStrong, in: .circle)
        }
        .buttonStyle(.plain)
    }

    private var nextButton: some View {
        Button {
            Task { await self.playerService.next() }
            HapticService.playback()
        } label: {
            Image(systemName: "forward.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .compatGlass(interactive: true, tint: Theme.Colors.surfaceStrong, in: .circle)
        }
        .buttonStyle(.plain)
    }

    private var progressLine: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.16))
                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(width: max(0, proxy.size.width * self.progressFraction))
            }
        }
        .frame(height: 2)
    }

    private var progressFraction: Double {
        guard self.playerService.duration > 0 else { return 0 }
        return self.playerService.progress / self.playerService.duration
    }

    private var accessibilityLabel: String {
        let title = self.playerService.currentTrack?.title ?? "Loading"
        let artist = self.playerService.currentTrack?.artistsDisplay ?? ""
        return artist.isEmpty ? "Now Playing, \(title)" : "Now Playing, \(title), \(artist)"
    }

    private var artworkURL: URL? {
        self.playerService.currentTrack?.displayThumbnailURL
    }

    private func openNowPlaying() {
        withAnimation(AppAnimation.spring) {
            self.isNowPlayingPresented = true
        }
    }
}
