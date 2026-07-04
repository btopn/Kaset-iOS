import SwiftUI

// MARK: - PlaylistCreationCoordinator

/// Single, app-wide coordinator for the "create playlist" sheet.
///
/// Why centralized: on macOS Kaset presented create-playlist via `NSAlert`
/// from two independent call sites (`SongActionsHelper`, the add-to-playlist
/// submenu). On iOS there is one idiomatic way to do this — a SwiftUI sheet —
/// so instead of rebuilding the dialog twice, both call sites route through
/// this coordinator. A view presents the sheet once by observing
/// `PlaylistCreationCoordinator.shared`.
@MainActor
@Observable
final class PlaylistCreationCoordinator {
    static let shared = PlaylistCreationCoordinator()

    /// A request to create a playlist, optionally seeded with a video.
    struct Request: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let seedVideoId: String?
        let seedThumbnailURL: URL?
        let onCreated: ((Playlist) -> Void)?
    }

    /// The active request, when non-nil the host view presents the sheet.
    private(set) var activeRequest: Request?

    /// Optional prefill song title shown to the user.
    private(set) var prefillTitle: String = ""

    private var client: (any YTMusicClientProtocol)?

    private init() {}

    /// Wires the API client used to perform the creation. Called once at launch.
    func configure(client: any YTMusicClientProtocol) {
        self.client = client
    }

    /// Requests creation of a new private playlist, optionally seeded with a song.
    func request(
        title fallbackTitle: String = "",
        message: String,
        seedVideoId: String? = nil,
        seedThumbnailURL: URL? = nil,
        onCreated: ((Playlist) -> Void)? = nil
    ) {
        self.prefillTitle = fallbackTitle
        self.activeRequest = Request(
            title: fallbackTitle,
            message: message,
            seedVideoId: seedVideoId,
            seedThumbnailURL: seedThumbnailURL,
            onCreated: onCreated
        )
    }

    /// Called by the presented sheet when the user confirms creation.
    func create(title: String) async {
        guard let request = activeRequest, let client else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let playlistId = try await client.createPlaylist(
                title: trimmed,
                description: nil,
                privacyStatus: .private,
                videoIds: request.seedVideoId.map { [$0] } ?? []
            )
            let playlist = Playlist(
                id: playlistId,
                title: trimmed,
                description: nil,
                thumbnailURL: request.seedThumbnailURL,
                trackCount: request.seedVideoId == nil ? 0 : 1
            )
            SongActionsHelper.invalidateLibraryResponseCaches()
            LibraryMutationBroadcaster.shared.playlistCreated(playlist)
            try? await Task.sleep(for: .milliseconds(500))
            SongActionsHelper.invalidateLibraryResponseCaches()
            await LibraryMutationBroadcaster.shared.reconcileCreatedPlaylist(playlist)
            request.onCreated?(playlist)
        } catch {
            DiagnosticsLogger.ui.error("Failed to create playlist: \(error.localizedDescription)")
        }
        activeRequest = nil
    }

    /// Cancels the active request (user dismissed the sheet).
    func cancel() {
        activeRequest = nil
    }
}

// MARK: - PlaylistDeletionCoordinator

/// Single, app-wide coordinator for the "delete playlist" confirmation dialog.
///
/// Mirrors `PlaylistCreationCoordinator`: macOS Kaset used `NSAlert` from
/// `SongActionsHelper`; on iOS we present a `.confirmationDialog` from one
/// host view that observes this coordinator.
@MainActor
@Observable
final class PlaylistDeletionCoordinator {
    static let shared = PlaylistDeletionCoordinator()

    /// A pending deletion request.
    struct Request: Identifiable {
        let id = UUID()
        let playlist: Playlist
        let client: any YTMusicClientProtocol
        let libraryViewModel: LibraryViewModel?
        let onSuccess: (() -> Void)?
    }

    /// The active deletion request, when non-nil the host presents a confirmation.
    private(set) var activeRequest: Request?

    /// A transient error to surface if deletion fails.
    private(set) var deletionError: String?

    private init() {}

    /// Records a deletion request for the host view to confirm.
    func request(
        playlist: Playlist,
        client: any YTMusicClientProtocol,
        libraryViewModel: LibraryViewModel?,
        onSuccess: (() -> Void)? = nil
    ) {
        self.activeRequest = Request(
            playlist: playlist,
            client: client,
            libraryViewModel: libraryViewModel,
            onSuccess: onSuccess
        )
    }

    /// Confirms and performs the deletion. Called by the confirmation dialog.
    func confirm() async {
        guard let request = activeRequest else { return }
        do {
            try await SongActionsHelper.deletePlaylist(
                request.playlist,
                client: request.client,
                libraryViewModel: request.libraryViewModel
            )
            request.onSuccess?()
        } catch {
            deletionError = error.localizedDescription
        }
        activeRequest = nil
    }

    /// Cancels the active request (user dismissed the confirmation).
    func cancel() {
        activeRequest = nil
    }

    /// Clears a surfaced deletion error.
    func clearError() {
        deletionError = nil
    }
}

// MARK: - Playlist Coordinators Host Modifier

/// Attaches the centralized playlist create/delete presentations to a view.
///
/// Attach once near the root of the app; every feature then calls
/// `PlaylistCreationCoordinator.shared.request(...)` or
/// `PlaylistDeletionCoordinator.shared.request(...)` without each having to
/// declare its own sheet/alert state.
struct PlaylistCoordinatorsHost: ViewModifier {
    @State private var creation = PlaylistCreationCoordinator.shared
    @State private var deletion = PlaylistDeletionCoordinator.shared

    func body(content: Content) -> some View {
        content
            .sheet(item: self.creation.activeRequestAsBinding) { request in
                CreatePlaylistSheet(
                    prefillTitle: self.creation.prefillTitle,
                    message: request.message
                ) { title in
                    Task { await self.creation.create(title: title) }
                } onCancel: {
                    self.creation.cancel()
                }
                .presentationDetents([.medium, .large])
            }
            .confirmationDialog(
                "Delete “\(self.deletion.activeRequest?.playlist.title ?? "")”?",
                isPresented: self.deletion.isConfirmedBinding,
                titleVisibility: .visible
            ) {
                Button("Delete Playlist", role: .destructive) {
                    Task { await self.deletion.confirm() }
                }
                Button("Cancel", role: .cancel) {
                    self.deletion.cancel()
                }
            } message: {
                Text("This permanently deletes the playlist from YouTube Music. You can only delete playlists you created.")
            }
            .alert(
                "Unable to Delete Playlist",
                isPresented: self.deletion.hasErrorBinding
            ) {
                Button("OK", role: .cancel) {
                    self.deletion.clearError()
                }
            } message: {
                Text(self.deletion.deletionError ?? "")
            }
    }
}

extension PlaylistCreationCoordinator {
    /// Binding shim so `PlaylistCoordinatorsHost` can drive `.sheet(item:)`.
    var activeRequestAsBinding: Binding<Request?> {
        Binding(
            get: { self.activeRequest },
            set: { newValue in if newValue == nil { self.cancel() } }
        )
    }
}

extension PlaylistDeletionCoordinator {
    var isConfirmedBinding: Binding<Bool> {
        Binding(
            get: { self.activeRequest != nil },
            set: { newValue in if !newValue { self.cancel() } }
        )
    }

    var hasErrorBinding: Binding<Bool> {
        Binding(
            get: { self.deletionError != nil },
            set: { newValue in if !newValue { self.clearError() } }
        )
    }
}

extension View {
    /// Attaches the centralized playlist create/delete presentations.
    func hostingPlaylistCoordinators() -> some View {
        modifier(PlaylistCoordinatorsHost())
    }
}
