import Foundation
import SwiftUI

// MARK: - LikeDislikeContextMenu

/// Reusable context menu items for like/dislike actions.
struct LikeDislikeContextMenu: View {
    let song: Song
    let likeStatusManager: SongLikeStatusManager

    var body: some View {
        // Show Unlike if already liked, otherwise show Like
        if self.likeStatusManager.isLiked(self.song) {
            Button {
                SongActionsHelper.unlikeSong(self.song, likeStatusManager: self.likeStatusManager)
            } label: {
                Label("Unlike", systemImage: "hand.thumbsup.fill")
            }
        } else {
            Button {
                SongActionsHelper.likeSong(self.song, likeStatusManager: self.likeStatusManager)
            } label: {
                Label("Like", systemImage: "hand.thumbsup")
            }

            // Only show Dislike if not already liked
            if self.likeStatusManager.isDisliked(self.song) {
                Button {
                    SongActionsHelper.undislikeSong(self.song, likeStatusManager: self.likeStatusManager)
                } label: {
                    Label("Remove Dislike", systemImage: "hand.thumbsdown.fill")
                }
            } else {
                Button {
                    SongActionsHelper.dislikeSong(self.song, likeStatusManager: self.likeStatusManager)
                } label: {
                    Label("Dislike", systemImage: "hand.thumbsdown")
                }
            }
        }
    }
}

// MARK: - AddToQueueContextMenu

/// Reusable context menu items for adding songs to the queue.
struct AddToQueueContextMenu: View {
    let song: Song
    let playerService: PlayerService

    var body: some View {
        Button {
            SongActionsHelper.addToQueueNext(self.song, playerService: self.playerService)
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }

        Button {
            SongActionsHelper.addToQueueLast(self.song, playerService: self.playerService)
        } label: {
            Label("Add to Queue", systemImage: "text.append")
        }
    }
}

// MARK: - AddToPlaylistContextMenu

/// Reusable context-menu submenu for adding a song to one of the user's playlists.
///
/// Create-playlist is routed through the centralized
/// `PlaylistCreationCoordinator` so the sheet UI lives in exactly one place.
struct AddToPlaylistContextMenu: View {
    let song: Song
    let client: any YTMusicClientProtocol

    @State private var loadState: PlaylistLoadState = .idle

    private static let playlistLoadTimeout: Duration = .seconds(12)

    private enum PlaylistLoadError: Error {
        case timedOut
    }

    private enum PlaylistLoadState {
        case idle
        case loading
        case loaded(AddToPlaylistMenu)
        case failed(String)
    }

    var body: some View {
        Menu {
            Group {
                switch self.loadState {
                case .idle, .loading:
                    Label("Loading Playlists…", systemImage: "hourglass")

                case let .loaded(menu):
                    if menu.options.isEmpty {
                        Label("No Playlists", systemImage: "music.note.list")
                    } else {
                        ForEach(menu.options) { option in
                            Button {
                                Task {
                                    await SongActionsHelper.addSongToPlaylist(
                                        self.song,
                                        playlist: option,
                                        client: self.client
                                    )
                                }
                            } label: {
                                Label(
                                    option.title,
                                    systemImage: option.isSelected ? "checkmark.circle.fill" : "music.note.list"
                                )
                            }
                            .disabled(option.isSelected)
                        }
                    }

                case let .failed(errorMessage):
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                    Button {
                        Task { await self.loadPlaylists(forceRefresh: true) }
                    } label: {
                        Label("Retry Loading Playlists", systemImage: "arrow.clockwise")
                    }
                }

                if self.canCreatePlaylist {
                    Divider()
                    self.createPlaylistButton
                }
            }
            .onAppear {
                self.startLoadingPlaylistsIfNeeded()
            }
        } label: {
            Label("Add to Playlist", systemImage: "text.badge.plus")
        }
        .onAppear {
            // Preload options so the submenu isn't stuck on "Loading…" on first open.
            self.startLoadingPlaylistsIfNeeded()
        }
    }

    private var canCreatePlaylist: Bool {
        guard case let .loaded(menu) = self.loadState else { return false }
        return menu.canCreatePlaylist
    }

    private var createPlaylistButton: some View {
        Button {
            PlaylistCreationCoordinator.shared.request(
                message: "Create a private playlist and add “\(self.song.title)” to it.",
                seedVideoId: self.song.videoId,
                seedThumbnailURL: self.song.thumbnailURL
            ) { _ in
                Task { await self.loadPlaylists(forceRefresh: true) }
            }
        } label: {
            Label("Create Playlist…", systemImage: "plus.rectangle.on.rectangle")
        }
    }

    private func startLoadingPlaylistsIfNeeded() {
        guard case .idle = self.loadState else { return }

        Task { await self.loadPlaylists(forceRefresh: false) }
    }

    private func loadPlaylists(forceRefresh: Bool = false) async {
        guard !Task.isCancelled else { return }
        self.loadState = .loading
        if forceRefresh {
            APICache.shared.invalidate(matching: "playlist/get_add_to_playlist:")
        }

        do {
            let menu = try await self.fetchAddToPlaylistOptionsWithTimeout()
            self.loadState = .loaded(menu)
        } catch is CancellationError {
            // Opening and closing menus can cancel view-scoped work. Keep the
            // submenu in the non-failed initial state so the next open retries
            // automatically instead of showing a manual retry before a real
            // request failure has occurred.
            self.loadState = .idle
        } catch {
            self.loadState = .failed("Unable to Load Playlists")
            DiagnosticsLogger.ui.error("Failed to load add-to-playlist options: \(error.localizedDescription)")
        }
    }

    private func fetchAddToPlaylistOptionsWithTimeout() async throws -> AddToPlaylistMenu {
        let client = self.client
        let videoId = self.song.videoId

        return try await withThrowingTaskGroup(of: AddToPlaylistMenu.self) { group in
            group.addTask {
                try await client.getAddToPlaylistOptions(videoId: videoId)
            }

            group.addTask {
                try await Task.sleep(for: Self.playlistLoadTimeout)
                throw PlaylistLoadError.timedOut
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw CancellationError()
            }

            return result
        }
    }
}
