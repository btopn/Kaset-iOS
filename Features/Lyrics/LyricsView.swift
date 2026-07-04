import SwiftUI

// MARK: - LyricsView

/// Plain and synced lyrics for the current track.
///
/// Falls back gracefully when no lyrics are available. Highlights the active
/// line when synced timing data is present.
struct LyricsView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(SyncedLyricsService.self) private var lyricsService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingM) {
                    switch self.lyricsService.currentLyrics {
                    case .unavailable:
                        EmptyStateView(
                            title: "No Lyrics",
                            message: "Lyrics aren't available for this track.",
                            systemImage: "text.quote"
                        )
                        .padding(.top, Theme.spacingXXXL)
                        .frame(maxWidth: .infinity)

                    case let .plain(lyrics):
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                    case let .synced(synced):
                        ForEach(Array(synced.lines.enumerated()), id: \.offset) { _, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, Theme.spacingXL)
                .padding(.vertical, Theme.spacingL)
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { self.dismiss() }
                }
            }
        }
        .task(id: self.currentTrackId) {
            await self.fetchLyrics()
        }
    }

    private var currentTrackId: String {
        self.playerService.currentTrack?.videoId ?? ""
    }

    private func fetchLyrics() async {
        guard let track = self.playerService.currentTrack else { return }
        let info = LyricsSearchInfo(
            title: track.title,
            artist: track.artistsDisplay,
            album: track.album?.title,
            duration: track.duration,
            videoId: track.videoId
        )
        await self.lyricsService.fetchLyrics(for: info)
    }
}
