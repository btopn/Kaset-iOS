import SwiftUI

// MARK: - ScrubBar

/// The one reusable seek/scrub slider.
///
/// Used by both the mini `PlayerBar` and the full `NowPlayingView`. Tracks a
/// local seek value while dragging so playback doesn't stutter on every tick,
/// then commits to `playerService.seek(to:)` on release.
struct ScrubBar: View {
    @Environment(PlayerService.self) private var playerService

    @State private var seekValue: Double = 0
    @State private var isSeeking = false

    var showsTimes: Bool = true
    var height: CGFloat = 4

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let progress = self.displayProgress
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: self.height)
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: max(0, proxy.size.width * progress), height: self.height)
                }
                .frame(height: max(self.height, 24))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            self.isSeeking = true
                            let fraction = max(0, min(1, value.location.x / proxy.size.width))
                            self.seekValue = fraction
                        }
                        .onEnded { value in
                            let fraction = max(0, min(1, value.location.x / proxy.size.width))
                            let target = fraction * self.playerService.duration
                            self.isSeeking = false
                            Task { await self.playerService.seek(to: target) }
                        }
                )
            }
            .frame(height: max(self.height, 24))

            if self.showsTimes {
                HStack {
                    Text(Self.format(self.displayProgress * self.playerService.duration))
                    Spacer()
                    Text("-" + Self.format(max(0, self.playerService.duration - self.displayProgress * self.playerService.duration)))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .onChange(of: self.playerService.progress) { _, newValue in
            guard !self.isSeeking, self.playerService.duration > 0 else { return }
            self.seekValue = newValue / self.playerService.duration
        }
        .onChange(of: self.playerService.duration) { _, _ in
            guard !self.isSeeking, self.playerService.duration > 0 else { return }
            self.seekValue = self.playerService.progress / self.playerService.duration
        }
        .onAppear {
            if self.playerService.duration > 0 {
                self.seekValue = self.playerService.progress / self.playerService.duration
            }
        }
    }

    /// The fraction (0–1) to display: the live drag value while seeking,
    /// otherwise the observed progress.
    private var displayProgress: Double {
        self.isSeeking ? self.seekValue : (self.playerService.duration > 0
            ? self.playerService.progress / self.playerService.duration
            : 0)
    }

    /// Formats seconds as `m:ss` (or `h:mm:ss` for long durations).
    private static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
