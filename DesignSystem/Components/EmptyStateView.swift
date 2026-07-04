import SwiftUI

// MARK: - EmptyStateView

/// The one reusable empty-state component (e.g. empty queue, empty library).
struct EmptyStateView: View {
    let title: String
    var message: String? = nil
    var systemImage: String = "tray"

    var body: some View {
        ContentUnavailableView {
            Label(self.title, systemImage: self.systemImage)
        } description: {
            if let message {
                Text(message)
            }
        }
    }
}
