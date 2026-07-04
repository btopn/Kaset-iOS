import SwiftUI

// MARK: - Environment Values

/// Centralized custom `EnvironmentValues` for the app.
///
/// Per the reuse rule, every custom environment key lives here so there is a
/// single source of truth — features read them via `@Environment(\.key)`,
/// never by re-declaring keys elsewhere. Mirrors how Kaset's `KasetApp`
/// declares its environment surface in one place.
extension EnvironmentValues {
    /// Whether to render the legacy (pre-Liquid Glass) UI. Always `false` on
    /// iOS, where Liquid Glass is always available. Retained so ported views
    /// that branch on this value compile without modification.
    @Entry var usesLegacyMacOS15UI: Bool = false

    /// Triggers search field focus when toggled.
    @Entry var searchFocusTrigger: Binding<Bool> = .constant(false)

    /// The current root navigation selection.
    @Entry var navigationSelection: Binding<TabItem?> = .constant(nil)

    /// The shared YouTube Music client, injected once at the root.
    @Entry var client: (any YTMusicClientProtocol)? = nil
}

// MARK: - TabItem

/// The top-level tabs shown in the iOS tab bar.
/// A standalone type (Kaset's `NavigationItem` is sidebar-oriented); the
/// feature views push their own destinations independently of this.
enum TabItem: Hashable, CaseIterable, Identifiable {
    case home
    case explore
    case library
    case search

    var id: Self { self }
}
