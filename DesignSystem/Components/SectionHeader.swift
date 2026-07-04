import SwiftUI

// MARK: - SectionHeader

/// The one shelf/section header, reused on Home, Explore, Charts, Library, etc.
///
/// Shows a title and an optional "See All" affordance. Mirrors Kaset's macOS
/// shelf header but as a self-contained iOS component.
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var showsSeeAll: Bool = false
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(self.title)
                    .font(.title2)
                    .fontWeight(.bold)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if self.showsSeeAll, self.onSeeAll != nil {
                Button("See All") {
                    self.onSeeAll?()
                }
                .font(.subheadline)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, Theme.spacingXL)
    }
}
