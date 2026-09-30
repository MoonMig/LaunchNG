# LaunchNG

**Languages**: [English](README.md) | [简体中文](i18n/README.zh.md) | [繁體中文](i18n/README.zh-TW.md) | [日本語](i18n/README.ja.md) | [한국어](i18n/README.ko.md) | [Français](i18n/README.fr.md) | [Español](i18n/README.es.md) | [Deutsch](i18n/README.de.md) | [Русский](i18n/README.ru.md) | [हिन्दी](i18n/README.hi.md) | [Tiếng Việt](i18n/README.vi.md) | [Italiano](i18n/README.it.md) | [Čeština](i18n/README.cs.md)

macOS Tahoe (26) removed Launchpad outright. LaunchNG brings it back as a native app: it reads your existing Launchpad layout straight out of macOS's own database on first run, then reimplements paging, folders, search, and drag-and-drop reordering on top of a Core Animation-rendered grid, with Dock integration, a bundled CLI/TUI, and a signed, in-app auto-updater.

## Download

**[Get the latest release](https://github.com/moonmig/LaunchNG/releases/latest)**

If you find this useful, a star on the repo is appreciated. LaunchNG began as a fork of [LaunchNext](https://github.com/RoversX/LaunchNext) by RoversX — the original project is worth a star too.

<!-- Screenshots go here — see Contributing if you'd like to submit current ones. -->

### If macOS blocks the app on first launch

Releases are unsigned/ad-hoc builds (no paid Apple Developer account is used for this fork), so Gatekeeper will refuse to open the app until you clear the quarantine flag once:

```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNG.app
```

Only run this against apps you actually trust — it disables macOS's download-quarantine check for that app.

Building from source instead? See [Configure local code signing](#configure-local-code-signing) below; you won't need this command.

## What it does

- **One-click import from the real Launchpad database** — reads `/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db` directly and reconstructs your existing folders, positions, and pages exactly as they were
- **The classic paged-grid experience** — search, keyboard navigation, drag-and-drop reordering, folder creation by dragging one icon onto another
- **Core Animation rendering throughout**, including drag-and-drop straight into the Dock and native Liquid Glass folder icons on macOS 26
- **Folder layouts**: paged (like the original) or vertical scrolling, per your preference
- **Fuzzy search** with CJK (pinyin/romanization) matching, so partial or imperfect input still finds the right app
- **Hot corner and trackpad gesture activation**, including experimental 4/5-finger pinch and tap support
- **A CLI and TUI** for inspecting or scripting your layout from the terminal
- **Signed automatic updates** via [Sparkle](https://sparkle-project.org), with a normal in-app "Check for Updates"
- **Local backups** to a folder of your choice, with a managed history you can restore from
- **Hide app icon labels, resize icons, adjust spacing** — independently for the main grid and for folder contents
- **13 languages** with full UI translation (see the language list above)
- **Context menu actions** — show in Finder, copy app path, rename folders, and (opt-in) a Gatekeeper-unblock shortcut for other apps you trust
- **Controller and voice-feedback support** for accessibility-minded setups

## What macOS Tahoe took away

- No user-created folders or custom organization
- No drag-and-drop rearranging
- No visual app management at all — just an automatically generated, alphabetized grid you can't touch

LaunchNG exists because that's a real downgrade, not a reasonable default.

## Where your data lives

LaunchNG's own layout, preferences, and cache live in:

```
~/Library/Application Support/LaunchNG/Data.store
```

Nothing is sent anywhere. The only network activity is checking the update feed and, when you choose to import it, reading Apple's own Launchpad database at:

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Installation

### Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon or Intel
- Xcode 26, if building from source

### Build from source

```bash
git clone https://github.com/moonmig/LaunchNG.git
cd LaunchNG
open LaunchNG.xcodeproj
```

<a name="configure-local-code-signing"></a>**Configure local code signing** (no paid Apple Developer account needed):

- Select the **LaunchNG** target → **Signing & Capabilities** → set **Team** to `None`, certificate to `Sign to Run Locally`. Leave Hardened Runtime on.
- Xcode will mark the project file as modified after this — don't include signing-only changes in a pull request.

To run with `⌘R`, the destination must be **My Mac** — a universal/"Any Mac" destination can build and archive but can't launch for debugging. `⌘B` to just build.

### Command-line build

```bash
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release

# Universal binary (Apple Silicon + Intel):
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Using it

1. **First launch** scans your installed applications automatically.
2. **Settings → General → Import System Launchpad** pulls in your existing layout, folders, and positions in one click.
3. Click to select, double-click (or Return) to launch; type anywhere to search.
4. Drag one app onto another to create a folder; drag apps around to reorder.
5. Optionally enable the CLI in Settings if you want to script your layout from the terminal.

### Fullscreen vs. compact

- **Fullscreen** covers the whole screen, closest to the original Launchpad.
- **Compact** is a floating, rounded window you can resize.
- Appearance settings (icon scale, spacing, page-indicator position, and more) are tracked separately for each mode.
- Fullscreen can optionally hide the menu bar; macOS hides the Dock automatically when that's on.

## Notable settings

- **Appearance**: icon scale, label size and visibility, grid spacing — with separate values for folder contents — plus a background style (blur, native Liquid Glass, or a live wallpaper-derived backdrop)
- **Search**: fuzzy matching toggle and search debounce timing
- **Hidden apps**: keep specific apps out of the grid without uninstalling them
- **Backup**: pick a folder, create timestamped backups, restore or delete old ones from a list
- **Shortcut & gesture**: the global hotkey, hot corner, and (experimental) trackpad gesture bindings
- **Updates**: automatic-check toggle and a manual "Check for Updates" button, both backed by Sparkle

## Troubleshooting

**The app won't start.** Confirm you're on macOS 26.0 or later and that the quarantine flag has been cleared (see above).

**"Check for Updates" says something's wrong.** LaunchNG uses Sparkle with a signed update feed; a manual check should always reflect the latest published release within a few minutes.

**The `launchng` terminal command isn't there.** It's opt-in — enable the command line interface in Settings first, and LaunchNG will install (and can later remove) the managed shim itself.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Commit your changes with a clear message
4. Push the branch and open a pull request

A few things that help review go smoothly:
- Keep signing-only Xcode project changes out of your diff (see local code signing above)
- If you're touching the Core Animation grid, check `GridReorderPlan.swift` first — reorder/paging logic belongs there, not duplicated per view
- Run the test suite before opening a PR:
  ```bash
  xcodebuild test -scheme LaunchNG -destination 'platform=macOS'
  ```

Fresh, current screenshots (main grid, a couple of Settings tabs) are also genuinely useful contributions — see the placeholder near the top of this file.

### Further documentation

- [Folder Liquid Glass](Documentation/FolderLiquidGlass.md) — design constraints behind the folder glass icons, what's verified, and what still needs acceptance testing
- [Grid diagnostics](scripts/diagnostics/README.md) — manual probes for the grid and glass overlay, with their exact coverage and limits

## License and attribution

LaunchNG is a fork of [LaunchNext](https://github.com/RoversX/LaunchNext) by RoversX, which in turn traces back to the broader Launchpad-replacement community effort. Both projects are licensed GPL-3.0, and LaunchNG follows the same terms — see [LICENSE](LICENSE).

Experimental trackpad gesture support is built on [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) and the fork by [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport).

---

![GitHub downloads](https://img.shields.io/github/downloads/moonmig/LaunchNG/total)
