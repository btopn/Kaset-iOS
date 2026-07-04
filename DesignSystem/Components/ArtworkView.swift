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
            ZStack {
                Color(.tertiarySystemFill)
                Image(systemName: "music.note")
                    .font(.system(size: min(self.targetSize.width, self.targetSize.height) * 0.35))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: self.targetSize.width, height: self.targetSize.height)
        .clipShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
    }
}
