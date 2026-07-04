import SwiftUI

// MARK: - PlayerBar

/// Compact player bar pinned above the tab bar.
///
/// Shows current artwork/title in one pill and playback controls in another.
/// Tapping the bar expands the full `NowPlayingView`. Hosts the hidden
/// playback WebView when a track is pending.
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
        HStack(spacing: Theme.spacingS) {
            self.trackPill
            self.controlsPill
        }
        .frame(maxWidth: 330)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.spacingM)
        .padding(.bottom, Theme.spacingS)
    }

    private var trackPill: some View {
        HStack(spacing: Theme.spacingS) {
            ArtworkView(
                url: self.artworkURL,
                targetSize: .init(width: 36, height: 36),
                cornerRadius: 9
            )
            .matchedGeometryEffect(id: "player-artwork", in: self.namespace, isSource: !self.isNowPlayingPresented)
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
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
        }
        .padding(.leading, 8)
        .padding(.trailing, Theme.spacingM)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .compatGlass(interactive: true, tint: Theme.Colors.glassTint, in: Capsule())
        .matchedGeometryEffect(id: "player-surface", in: self.namespace, isSource: !self.isNowPlayingPresented)
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
        .contentShape(Capsule())
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

    private var controlsPill: some View {
        HStack(spacing: 2) {
            self.playPauseButton
            self.nextButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .compatGlass(interactive: true, tint: Theme.Colors.glassTint, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }

    private var playPauseButton: some View {
        Button {
            Task { await self.playerService.playPause() }
            HapticService.playback()
        } label: {
            Image(systemName: self.playerService.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
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
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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
