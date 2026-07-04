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

    var body: some View {
        if self.playerService.currentTrack != nil || self.playerService.pendingPlayVideoId != nil {
            self.content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.spacingM) {
                ArtworkView(
                    url: self.playerService.currentTrack?.thumbnailURL,
                    targetSize: .init(width: 44, height: 44),
                    cornerRadius: Theme.cornerRadiusS
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(self.playerService.currentTrack?.title ?? "Loading…")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Text(self.playerService.currentTrack?.artistsDisplay ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    Task { await self.playerService.playPause() }
                    HapticService.playback()
                } label: {
                    Image(systemName: self.playerService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await self.playerService.next() }
                    HapticService.playback()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.spacingM)
            .padding(.vertical, Theme.spacingS)
            .contentShape(Rectangle())
            .onTapGesture {
                self.isNowPlayingPresented = true
            }

            // Thin progress indicator beneath the bar.
            ProgressView(value: self.progressFraction)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .padding(.horizontal, Theme.spacingM)
                .padding(.bottom, 2)
        }
        .background(.bar)
    }

    private var progressFraction: Double {
        guard self.playerService.duration > 0 else { return 0 }
        return self.playerService.progress / self.playerService.duration
    }
}
