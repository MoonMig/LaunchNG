# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

LaunchNG is a native macOS (Tahoe/26+) SwiftUI + AppKit app that replaces the
Launchpad that Apple removed. It imports the user's existing Launchpad layout
straight from the system SQLite database, then re-implements paging, folders,
search, drag-and-drop reordering, and Dock integration on top of two
interchangeable rendering engines. It also ships a CLI/TUI and a bundled
GUI-less auto-updater.

## Build, run, test

Requires Xcode 26 and macOS 26 (Tahoe). No paid Apple Developer account is
needed for local builds.

```bash
open LaunchNG.xcodeproj
```

- To run with `⌘+R`, the run destination must be **My Mac**, not **Any Mac**
  (universal/"Any Mac" builds cannot launch for debugging).
- Local signing: target **LaunchNG** → Signing & Capabilities → Team =
  `None`, certificate = `Sign to Run Locally`, Hardened Runtime stays on.
  Xcode will mark the project file dirty after this — never include
  signing-only diffs in a PR.

Command-line build:

```bash
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release
# Universal binary:
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

Unit tests (target `LaunchNGTests`):

```bash
xcodebuild test -scheme LaunchNG -destination 'platform=macOS'
# Single test class:
xcodebuild test -scheme LaunchNG -destination 'platform=macOS' \
  -only-testing:LaunchNGTests/GridReorderPlanTests
```

Release packaging lives in `scripts/`: `release.sh` (unsigned zip build) and
`release-notarized.sh` (Developer ID sign + notarize, see `--help`).

### Manual diagnostics (not CI, not shipped)

`scripts/diagnostics/` contains standalone probes for the Core Animation grid
and folder Liquid Glass overlay — some compile real production files with a
synthetic host, one (`run_folder_merge_integration.py`) builds the actual app
target with a swapped entry point. They require an unlocked GUI desktop and
are not lint or regression gates. Read `scripts/diagnostics/README.md` before
trusting or citing their output — it documents exactly what each probe does
and does **not** verify (no AppStore, no real persistence, process-level
CPU/timer numbers only). Design rationale and verification status for the
folder glass feature live in `Documentation/FolderLiquidGlass.md`.

## Architecture

### Targets

- **LaunchNG** — the app (SwiftUI + AppKit, `@main` in `LaunchpadApp.swift`).
- **LaunchNGTests** — XCTest bundle.
- **LaunchNGContextMenuCore** — static library: pure app-context-menu model
  logic (`AppContextMenuModel.swift`), split out so it's independently
  testable.
- **LaunchNGWallpaperCore** — static library: wallpaper snapshot/identity/
  caching logic used by the fullscreen background, also independently
  testable.

Self-updates go through **Sparkle** (SPM dependency on the `LaunchNG` target
only, `SparkleUpdaterController.swift` wraps `SPUStandardUpdaterController`).
`appcast.xml` at the repo root (served to the app via
`raw.githubusercontent.com` — see `SUFeedURL` in the target's build
settings) is the feed; `scripts/sparkle-tools/bin/` holds vendored Sparkle
CLI binaries (`sign_update`, `generate_appcast`, `BinaryDelta`) that the
release scripts use to sign each release asset and append its appcast
entry. The EdDSA private key used to sign releases lives only in the
release-builder's macOS Keychain — it is never checked into the repo.

### App lifecycle and window management

`AppDelegate` (in `LaunchpadApp.swift`, 70KB+) is the real entry point: it owns
`AppStore`, a single `NSWindow` (`BorderlessWindow`) that the whole UI lives
in, the global hotkey (via Carbon `RegisterEventHotKey`), the CLI IPC server,
and the hot-corner/gesture monitors. `applicationDidFinishLaunching` first
checks `runHeadlessModeIfRequested()` — the same binary boots into GUI, TUI,
or one-shot CLI mode depending on how it was invoked (see below).

### AppStore — the central state container

`AppStore.swift` (~320KB, one `final class AppStore: ObservableObject`) is the
app's single source of truth: app/folder layout, pages, persistence
(SwiftData `ModelContainer`), search state, settings/preferences, import from
native Launchpad, hotkey/gesture preferences, update checking, and more. Most
other files are views or engines that read/mutate `AppStore` — when tracing
"where does X live," start there. It's huge; grep for the relevant
`@Published` property or method name rather than reading top to bottom.

### Two rendering engines

Settings expose **Legacy Engine** (pure SwiftUI grid, `LaunchpadView.swift`,
`LaunchpadItemButton.swift`) and **Next Engine + Core Animation**
(`CAGridView.swift` + its `CAGridView+*.swift` extensions: `Input`, `Layout`,
`DragLanding`, `DropPreview`, `FolderCreation`, `FolderDissolve`,
`FolderGlass`, `FolderMerge`) wrapped for SwiftUI via
`CAGridViewRepresentable.swift`. The CA engine is the recommended/default
path and is where drag-and-drop-to-Dock and Liquid Glass folder icons live.
Folder-open/close presentation for the CA engine is driven by
`CAFolderPresentation.swift` + `CAFolderGridView.swift`
(`CAFolderGridViewRepresentable.swift`), with `FolderGlassOverlay.swift`
rendering the native glass backplate and `FolderIconBitmapCache.swift`
caching rendered folder-icon bitmaps (byte-budgeted LRU). `PerformanceEngineSelector.swift`
/ `PerformanceMode.swift` pick between them. The legacy SwiftUI `FolderView.swift`
is the non-CA folder UI.

Grid reordering math is isolated in `GridReorderPlan.swift` — a pure,
side-effect-free algorithm (page compaction, cascade, new/emptied pages) that
both engines share and that has its own exhaustive unit test
(`GridReorderPlanTests`). Prefer changing behavior there over duplicating
reorder logic per-engine.

### Native Launchpad import

`NativeLaunchpadImporter.swift` reads Apple's own Launchpad SQLite DB
directly (path resolved via `getconf DARWIN_USER_DIR`, see README) using
`SQLite3` to reconstruct folders/positions/pages on first run or on-demand
import from Settings.

### Search

`Search/` is a self-contained module: `LaunchpadSearchEngine.swift` (the
engine `AppStore` queries), `FuzzyMatcher.swift`, `CJKTransliterator.swift`
(pinyin/romanization for CJK fuzzy matching), `SearchIndexEntry.swift`.

### Gestures / hot corner / controller input

`Gesture/` implements the experimental low-level trackpad gesture support
(4/5-finger pinch/tap) built on the vendored `OpenMultitouchSupport` fork
under `LaunchNG/ThirdParty/OpenMultitouchSupport/` (see `Config/OpenMultitouchSupport.xcconfig`).
`GestureStateMachine.swift` is the core state machine; `GestureMonitor.swift`
is what `AppDelegate` starts/stops. This is explicitly marked removable in
code comments (`AppDelegate` flags every gesture-related property/method it
would need deleted if gesture support is dropped) — treat it as an optional
subsystem when refactoring `AppDelegate`. `HotCornerMonitor.swift` and
`ControllerInputManager.swift` are separate, non-experimental activation
paths.

### CLI / TUI

`LaunchNGCLI.swift` parses `CommandLine.arguments` into `LaunchNGRuntimeMode`
(`.gui` / `.tui` / `.cli`): no args in an interactive terminal → TUI; no args
otherwise → normal GUI launch; `--cli <command> [args]` → one-shot headless
command execution; `--gui`/`--tui` force a mode. `LaunchNGCLIIPC.swift` is
the IPC transport a running GUI instance uses to accept CLI commands from a
second invocation (so `launchng --cli ...` can control an already-running
app). The installable `launchng` shell command is managed from in-app
Settings, not installed by default.

### Wallpaper / background

`BackgroundImageController.swift` (78KB) drives the live wallpaper-derived
background behind the fullscreen grid; `WallpaperContextMonitor.swift`,
`WallpaperScreenCapture.swift`, `WallpaperDiagnostics.swift` support it in the
app target, while the reusable, independently-tested logic (identity,
frame-stability, cache budget, aerial-preview handling, image rendering) is
factored out into the `LaunchNGWallpaperCore` static library and covered by
`LaunchNGTests/Wallpaper*Tests.swift`.

### Localization

`Localization.swift` (~600KB generated/maintained string table) plus one
`.lproj` per language at the repo root (`en`, `zh-Hans`, `zh-Hant`, `ja`,
`ko`, `fr`, `es`, `de`, `ru`, `hi`, `vi`, `it`, `cs`) drive in-app strings.
README translations live separately under `i18n/README.<lang>.md` and must be
updated alongside `README.md` — they are not auto-generated.

### Markdown rendering

`Markdown/` is a minimal, dependency-free Markdown renderer
(`SimpleMarkdownParser.swift` → `MarkdownRenderModel.swift`) used only to
render GitHub release notes in the in-app Update tab
(`ReleaseNotesMarkdownView.swift`).

## Conventions worth knowing

- Data persists to `~/Library/Application Support/LaunchNG/Data.store`
  (SwiftData) — never assume a fresh install has no state; `AppStore.migrateLegacyPreferencesIfNeeded()`
  runs before `AppStore()` is even constructed, so preference-schema changes
  need a migration path there.
- Some source comments in `AppDelegate` explicitly mark optional/experimental
  subsystems (AI overlay hotkey, gesture monitor) as commented-out or
  removable — check for `// ` prefixed blocks before assuming a feature is
  dead versus just disabled.
- Diagnostics/probe code in `scripts/diagnostics/` intentionally duplicates
  simplified model types to host production extensions in isolation; it can
  silently drift from production shape. It is not a substitute for the real
  `LaunchNGTests` suite or manual acceptance on device.
