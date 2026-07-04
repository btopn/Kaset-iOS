import Foundation

// MARK: - PlayerBarNavigationAction

/// Centralized callbacks the player bar uses to navigate to the currently
/// playing track's artist or album.
///
/// A single type reused by every view that hosts a player bar — features
/// construct it with their own navigation path append closures, so there is
/// exactly one navigation-action shape in the app instead of per-view closures.
struct PlayerBarNavigationAction: Hashable {
    var openArtist: ((Artist) -> Void)?
    var openAlbum: ((Playlist) -> Void)?

    /// A no-op action used where navigation is unavailable (e.g. previews).
    static let disabled = PlayerBarNavigationAction()

    func hash(into hasher: inout Hasher) {
        // Identity by reference identity of the closures is not required; this
        // type is used as a value passed into modifiers, not as identity.
    }

    static func == (lhs: PlayerBarNavigationAction, rhs: PlayerBarNavigationAction) -> Bool {
        true
    }
}
