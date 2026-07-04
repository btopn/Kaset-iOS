# Kaset iOS

A native iOS client for YouTube Music, ported from [Kaset](https://github.com/sozercan/kaset) (macOS). Built with Swift and SwiftUI, targeting iOS 26.0+ (Liquid Glass).

Plays DRM-protected YouTube Music content through a hidden `WKWebView` — the same architecture as the macOS original — using your existing YouTube Premium subscription.

## Status

**Builds and launches** on the iOS 26.5 simulator. Login flow (real Google sign-in via embedded WKWebView), the tabbed main UI (Home / Explore / Search / Library), and the playback surface (PlayerBar, NowPlaying with in-app music video, Queue, Lyrics) are wired up.

## What's ported

| Layer | Approach |
|---|---|
| Models (24 files), Parsers (15 files), `YTMusicClient`, `APICache`, `InnerTubeSupport` | **Verbatim** — pure Foundation/CryptoKit |
| ViewModels (13 files) | **Verbatim** — `@Observable` + Foundation |
| Auth (`AuthService`, `AccountService`), Library, Favorites, Settings, Lyrics, Notification | **Verbatim** — framework-free |
| `WebKitManager` (cookie/Keychain/SAPISID) | **Verbatim**, with the Web Extensions subsystem stripped |
| `PlayerService` + queue/album/playlist actions, `NowPlayingManager` | **Verbatim**, YouTube video-mode player dropped |
| `SingletonPlayerWebView` + JS bridge | Ported `NSViewRepresentable` → `UIViewRepresentable` |
| `ImageCache`, `CachedAsyncImage`, `ColorExtractor` | `NSImage` → `UIImage` |
| `HapticService` | `NSHapticFeedbackManager` → `UIFeedbackGenerator` |

## What's dropped (out of scope for this build)

- YouTube video source toggle (regular YouTube browsing) — music only
- System-wide Equalizer (CoreAudio process tap is macOS-only)
- Browser extensions (`WKWebExtensionController`)
- AppleScript / OSA scripting
- Sparkle auto-updates
- Scrobbling (Last.fm)

## Architecture

The codebase follows a clean, DRY structure. **`DesignSystem/` is the single home for shared components** — features import rather than re-roll:

- One `ArtworkView` (wraps `CachedAsyncImage`) — used by rows, cards, PlayerBar, NowPlaying
- One `SongRow` — every song list (History, Search, Playlist, Liked, Queue)
- One `SectionShelf` + `SectionCard` — every horizontal shelf (Home, Explore, Charts)
- One `PlayerControls` + `ScrubBar` — shared by PlayerBar and NowPlayingView
- One `NavigationBus` — relays card taps to the active tab's `NavigationStack`
- Centralized `PlaylistCreationCoordinator` / `PlaylistDeletionCoordinator` — one create/delete presentation each

```
App/            @main, AppDelegate (audio session), RootView (auth gate), Environment
DesignSystem/   Theme, Components (ArtworkView, SongRow, SectionShelf, PlayerControls, ScrubBar, ...), Modifiers
Navigation/     RootTabView, NavigationItem
Features/       Auth, Home, Explore, Library, Search, Playlist, Artist, Lyrics
Player/         PlayerService, PlayerWebView (WKWebView bridge), PlayerBar, NowPlayingView, QueueView
Services/       API, Auth, WebKit, Player, Library, Lyrics, Notification, ...
Models/         Song, Playlist, Artist, Album, ...
Views/          SharedViews (port of Kaset's reusable SwiftUI components), CachedAsyncImage
Utilities/      ImageCache, ColorExtractor, DiagnosticsLogger, LiquidGlassCompat, ...
```

## Build

Requires Xcode 26+ and the iOS 26.5 simulator runtime.

```bash
xcodegen generate
xcodebuild -project Kaset.xcodeproj -scheme Kaset \
  -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator build
```

The Xcode project is generated from `project.yml` (XcodeGen). Regenerate after adding/removing files.

## Disclaimer

Unofficial and not affiliated with YouTube or Google. "YouTube" and "YouTube Music" are trademarks of Google Inc.
