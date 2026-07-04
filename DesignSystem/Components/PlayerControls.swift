import SwiftUI

// MARK: - PlayerControls

/// The one reusable playback-control cluster: shuffle, previous, play/pause,
/// next, repeat. Used by both the mini `PlayerBar` and the full
/// `NowPlayingView`. A single component so the controls look and behave
/// identically everywhere.
struct PlayerControls: View {
    @Environment(PlayerService.self) private var playerService

    var size: ControlSize = .standard

    enum ControlSize {
        case compact
        case standard
        case large

        var primary: CGFloat { self == .large ? 72 : self == .standard ? 44 : 32 }
        var secondary: CGFloat { self == .large ? 36 : self == .standard ? 28 : 24 }
        var symbolScale: Image.Scale { self == .large ? .large : .medium }
    }

    var body: some View {
        HStack(spacing: self.size == .large ? 28 : 12) {
            self.shuffleButton
            self.previousButton
            self.playPauseButton
            self.nextButton
            self.repeatButton
        }
        .imageScale(self.size.symbolScale)
    }

    private var shuffleButton: some View {
        Button {
            self.playerService.toggleShuffle()
            HapticService.toggle()
        } label: {
            Image(systemName: "shuffle")
                .frame(width: self.size.secondary, height: self.size.secondary)
                .foregroundStyle(self.playerService.shuffleEnabled ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    private var previousButton: some View {
        Button {
            Task { await self.playerService.previous() }
            HapticService.playback()
        } label: {
            Image(systemName: "backward.fill")
                .frame(width: self.size.secondary, height: self.size.secondary)
        }
        .buttonStyle(.plain)
    }

    private var playPauseButton: some View {
        Button {
            Task { await self.playerService.playPause() }
            HapticService.playback()
        } label: {
            Image(systemName: self.playerService.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: self.size.primary * 0.5, weight: .semibold))
                .frame(width: self.size.primary, height: self.size.primary)
                .background(Color.accentColor, in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var nextButton: some View {
        Button {
            Task { await self.playerService.next() }
            HapticService.playback()
        } label: {
            Image(systemName: "forward.fill")
                .frame(width: self.size.secondary, height: self.size.secondary)
        }
        .buttonStyle(.plain)
    }

    private var repeatButton: some View {
        Button {
            self.playerService.cycleRepeatMode()
            HapticService.toggle()
        } label: {
            Image(systemName: self.repeatSymbol)
                .frame(width: self.size.secondary, height: self.size.secondary)
                .foregroundStyle(self.playerService.repeatMode != .off ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    private var repeatSymbol: String {
        switch self.playerService.repeatMode {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }
}
