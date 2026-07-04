import SwiftUI

// MARK: - QueueView

/// The upcoming play queue. Reuses `SongRow` for each entry and highlights
/// the currently playing track.
struct QueueView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if self.playerService.queue.isEmpty {
                        EmptyStateView(
                            title: "Queue is Empty",
                            message: "Play something to build a queue.",
                            systemImage: "list.bullet"
                        )
                        .padding(.top, Theme.spacingXXXL)
                    } else {
                        ForEach(Array(self.playerService.queue.enumerated()), id: \.element.id) { index, song in
                            QueueRow(song: song, isCurrent: index == self.playerService.currentIndex)
                        }
                    }
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { self.dismiss() }
                }
            }
        }
    }
}

// MARK: - QueueRow

/// A single row in `QueueView`: an indicator column + the shared `SongRow`.
private struct QueueRow: View {
    let song: Song
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            Group {
                if self.isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                        .font(.caption)
                }
            }
            .frame(width: 16)

            SongRow(song: self.song, showsLikeButton: false, showsDuration: true)
        }
        .background(self.isCurrent ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}
