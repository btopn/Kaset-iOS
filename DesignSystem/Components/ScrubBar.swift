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
    @State private var pendingSeekTarget: TimeInterval?

    var showsTimes: Bool = true
    var height: CGFloat = 4

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let progress = self.displayProgress
                let thumbSize: CGFloat = self.isSeeking ? 16 : 9
                let progressWidth = max(0, min(proxy.size.width, proxy.size.width * progress))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: self.height)
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: progressWidth, height: self.height)

                    Circle()
                        .fill(Color.primary)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: .black.opacity(self.isSeeking ? 0.35 : 0.18), radius: self.isSeeking ? 8 : 3, x: 0, y: 1)
                        .offset(x: max(0, min(proxy.size.width - thumbSize, progressWidth - thumbSize / 2)))
                        .animation(AppAnimation.snappy, value: self.isSeeking)
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
                            self.seekValue = fraction
                            self.pendingSeekTarget = target
                            Task {
                                await self.playerService.seek(to: target)
                                self.pendingSeekTarget = nil
                                self.isSeeking = false
                            }
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
            guard !self.isSeeking, self.pendingSeekTarget == nil, self.playerService.duration > 0 else { return }
            self.seekValue = newValue / self.playerService.duration
        }
        .onChange(of: self.playerService.duration) { _, _ in
            guard !self.isSeeking, self.pendingSeekTarget == nil, self.playerService.duration > 0 else { return }
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
        let value = self.isSeeking || self.pendingSeekTarget != nil ? self.seekValue : (self.playerService.duration > 0
            ? self.playerService.progress / self.playerService.duration
            : 0)
        return max(0, min(1, value))
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
