import UIKit

/// Centralized service for haptic feedback on iOS.
///
/// Wraps `UIFeedbackGenerator` so call sites stay platform-agnostic: every
/// feature calls `HapticService.playback()`, `HapticService.toggle()`, etc.,
/// and only this file knows about UIKit.
@MainActor
enum HapticService {
    /// Types of haptic feedback mapped to user actions.
    enum FeedbackType {
        /// Playback actions like play, pause, skip.
        case playbackAction
        /// Toggle actions like shuffle, repeat, like/dislike.
        case toggle
        /// Slider boundaries (volume/seek at limits).
        case sliderBoundary
        /// Navigation selection.
        case navigation
        /// Successful action completion (add to library).
        case success
        /// Action failure.
        case error
    }

    /// Whether haptic feedback is currently enabled.
    private static var isEnabled: Bool {
        guard SettingsManager.shared.hapticFeedbackEnabled else {
            return false
        }
        return !UIAccessibility.isReduceMotionEnabled
    }

    /// Performs haptic feedback of the specified type.
    static func perform(_ type: FeedbackType) {
        guard self.isEnabled else {
            DiagnosticsLogger.haptic.debug("Haptic feedback disabled, skipping \(String(describing: type))")
            return
        }

        DiagnosticsLogger.haptic.debug("Performing haptic feedback: \(String(describing: type))")

        switch type {
        case .playbackAction, .navigation:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .toggle, .sliderBoundary:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    /// Performs haptic feedback for a playback action (play, pause, skip).
    static func playback() {
        self.perform(.playbackAction)
    }

    /// Performs haptic feedback for a toggle action (shuffle, repeat, like).
    static func toggle() {
        self.perform(.toggle)
    }

    /// Performs haptic feedback when a slider reaches its boundary (0% or 100%).
    static func sliderBoundary() {
        self.perform(.sliderBoundary)
    }

    /// Performs haptic feedback for navigation selection.
    static func navigation() {
        self.perform(.navigation)
    }

    /// Performs haptic feedback for successful action completion.
    static func success() {
        self.perform(.success)
    }

    /// Performs haptic feedback for action failure.
    static func error() {
        self.perform(.error)
    }
}
