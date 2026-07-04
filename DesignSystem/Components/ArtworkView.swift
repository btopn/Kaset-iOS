import SwiftUI

// MARK: - ArtworkView

/// The single artwork component used everywhere a thumbnail appears:
/// `SongRow`, cards, `PlayerBar`, `NowPlayingView`, etc.
///
/// Wraps `CachedAsyncImage` so features never call `AsyncImage` or
/// `CachedAsyncImage` directly. Renders a rounded-rect image with a
/// deterministic placeholder (`music.note`) while loading and on failure.
struct ArtworkView: View {
    let url: URL?
    var targetSize: CGSize = .init(width: Theme.ArtworkSize.cardSmall, height: Theme.ArtworkSize.cardSmall)
    var cornerRadius: CGFloat = Theme.cornerRadiusM

    var body: some View {
        CachedAsyncImage(url: self.url, targetSize: self.targetSize) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            self.placeholder
        }
        .frame(width: self.targetSize.width, height: self.targetSize.height)
        .clipShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        LinearGradient(
            colors: self.placeholderColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "music.note")
                .font(.system(size: min(self.targetSize.width, self.targetSize.height) * 0.32, weight: .semibold))
                .foregroundStyle(.white.opacity(0.76))
        }
    }

    private var placeholderColors: [Color] {
        let seed = self.placeholderSeed
        let hue = Double(seed % 360) / 360
        return [
            Color(hue: hue, saturation: 0.72, brightness: 0.74),
            Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.64, brightness: 0.42),
            Color(hue: hue, saturation: 0.55, brightness: 0.18),
        ]
    }

    private var placeholderSeed: Int {
        (self.url?.absoluteString ?? "kaset").unicodeScalars.reduce(0) { partial, scalar in
            Int((UInt64(partial) &* 31 &+ UInt64(scalar.value)) % 10_000)
        }
    }
}
