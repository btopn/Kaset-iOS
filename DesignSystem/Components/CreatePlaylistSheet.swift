import SwiftUI

/// Reusable sheet for naming and creating a playlist.
///
/// Presented by `PlaylistCreationCoordinator`. Kept here (DesignSystem) so any
/// future feature that creates playlists reuses the exact same UI.
struct CreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @FocusState private var isFocused: Bool

    private let message: String
    private let onCreate: (String) -> Void
    private let onCancel: () -> Void

    init(prefillTitle: String, message: String, onCreate: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self._title = State(initialValue: prefillTitle)
        self.message = message
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Playlist name", text: self.$title)
                        .focused(self.$isFocused)
                        .submitLabel(.done)
                        .onSubmit(self.submit)
                } footer: {
                    Text(self.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        self.onCancel()
                        self.dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        self.submit()
                    }
                    .disabled(self.trimmedTitle.isEmpty)
                }
            }
        }
        .onAppear { self.isFocused = true }
    }

    private var trimmedTitle: String {
        self.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        let trimmed = self.trimmedTitle
        guard !trimmed.isEmpty else { return }
        self.onCreate(trimmed)
        self.dismiss()
    }
}
