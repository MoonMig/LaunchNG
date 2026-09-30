# LaunchNG

**Sprachen**: [English](../README.md) | [简体中文](README.zh.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

macOS Tahoe (26) hat Launchpad komplett entfernt. LaunchNG bringt es als native App zurück: Beim ersten Start liest es dein bestehendes Launchpad-Layout direkt aus der Datenbank von macOS aus und implementiert danach Paging, Ordner, Suche sowie Drag-and-Drop-Umsortierung selbst — auf einem mit Core Animation gerenderten Grid, mit Dock-Integration, einer mitgelieferten CLI/TUI und einem signierten Auto-Update direkt in der App.

## Herunterladen

**[Neueste Version holen](https://github.com/moonmig/LaunchNG/releases/latest)**

Wenn dir die App nützlich ist, freuen wir uns über einen Star im Repository. LaunchNG begann als Fork von [LaunchNext](https://github.com/RoversX/LaunchNext) von RoversX — auch das Originalprojekt verdient einen Star.

<!-- Screenshots kommen hierhin — siehe Abschnitt „Mitwirken", falls du aktuelle beisteuern möchtest. -->

### Wenn macOS den Start der App blockiert

Releases sind unsignierte/ad-hoc-Builds (dieser Fork nutzt keinen kostenpflichtigen Apple-Developer-Account), daher verweigert Gatekeeper das Öffnen der App, bis du einmal das Quarantäne-Flag entfernst:

```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNG.app
```

Führe diesen Befehl nur bei Apps aus, denen du wirklich vertraust — er deaktiviert für diese App die Download-Quarantäneprüfung von macOS.

Baust du aus dem Quellcode? Siehe [Lokale Code-Signierung einrichten](#configure-local-code-signing) weiter unten; diesen Befehl brauchst du dann nicht.

## Was LaunchNG bietet

- **Ein-Klick-Import aus der echten Launchpad-Datenbank** — liest `/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db` direkt aus und stellt deine vorhandenen Ordner, Positionen und Seiten exakt wieder her
- **Das klassische Erlebnis eines paginierten Grids** — Suche, Tastaturnavigation, Umsortieren per Drag-and-Drop, Ordner erstellen durch Ziehen eines Icons auf ein anderes
- **Durchgängiges Rendering mit Core Animation**, inklusive Drag-and-Drop direkt ins Dock und nativen Liquid-Glass-Ordnersymbolen unter macOS 26
- **Ordner-Layouts**: paginiert (wie das Original) oder vertikales Scrollen — ganz nach Wunsch
- **Unscharfe Suche** mit CJK-Transliterations-Matching (Pinyin usw.), sodass auch unvollständige oder ungenaue Eingaben die richtige App finden
- **Aktivierung per Hot Corner und Trackpad-Gesten**, inklusive experimenteller Unterstützung für 4-/5-Finger-Pinch und -Tap
- **Eine CLI und ein TUI**, um dein Layout im Terminal einzusehen oder zu scripten
- **Signierte automatische Updates** über [Sparkle](https://sparkle-project.org), mit einem gewöhnlichen „Nach Updates suchen"-Button in der App
- **Lokale Backups** in einen Ordner deiner Wahl, mit verwalteter Historie zum Wiederherstellen
- **App-Beschriftungen ausblenden, Icon-Größe und Abstände anpassen** — unabhängig voneinander für das Haupt-Grid und für Ordnerinhalte
- **13 Sprachen** mit vollständiger UI-Übersetzung (siehe Sprachliste oben)
- **Erweiterte Kontextmenüs** — im Finder anzeigen, App-Pfad kopieren, Ordner umbenennen und (optional) ein Shortcut zum Entfernen der Gatekeeper-Quarantäne bei anderen vertrauenswürdigen Apps
- **Controller- und Sprachfeedback-Unterstützung** für barrierefreiheitsorientierte Setups

## Was macOS Tahoe weggenommen hat

- Keine benutzerdefinierten Ordner oder freie Organisation
- Kein Umsortieren per Drag-and-Drop
- Überhaupt keine visuelle App-Verwaltung — nur ein automatisch generiertes, alphabetisch sortiertes Grid, das man nicht anfassen kann

LaunchNG existiert, weil das ein echter Rückschritt ist — kein vernünftiger Standard.

## Wo deine Daten liegen

Layout, Einstellungen und Cache von LaunchNG selbst liegen hier:

```
~/Library/Application Support/LaunchNG/Data.store
```

Es wird nichts irgendwohin gesendet. Die einzige Netzwerkaktivität ist die Prüfung des Update-Feeds und, wenn du dich dafür entscheidest, das Auslesen von Apples eigener Launchpad-Datenbank unter:

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Installation

### Voraussetzungen

- macOS 26 (Tahoe) oder neuer
- Apple Silicon oder Intel
- Xcode 26, falls aus dem Quellcode gebaut wird

### Aus dem Quellcode bauen

```bash
git clone https://github.com/moonmig/LaunchNG.git
cd LaunchNG
open LaunchNG.xcodeproj
```

<a name="configure-local-code-signing"></a>**Lokale Code-Signierung einrichten** (kein kostenpflichtiger Apple-Developer-Account nötig):

- Wähle das **LaunchNG**-Target → **Signing & Capabilities** → setze **Team** auf `None`, Zertifikat auf `Sign to Run Locally`. Hardened Runtime bleibt aktiviert.
- Xcode markiert die Projektdatei danach als geändert — nimm solche rein signaturbezogenen Änderungen nicht in einen Pull Request auf.

Zum Ausführen mit `⌘R` muss das Ziel **My Mac** sein — ein universelles/„Any Mac"-Ziel lässt sich bauen und archivieren, aber nicht zum Debuggen starten. `⌘B` nur zum Bauen.

### Build über die Kommandozeile

```bash
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release

# Universal Binary (Apple Silicon + Intel):
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Verwendung

1. **Beim ersten Start** werden deine installierten Anwendungen automatisch gescannt.
2. **Einstellungen → General → Import System Launchpad** übernimmt dein bestehendes Layout, Ordner und Positionen mit einem Klick.
3. Klick zum Auswählen, Doppelklick (oder Return) zum Starten; einfach tippen, um sofort zu suchen.
4. Eine App auf eine andere ziehen, um einen Ordner zu erstellen; Apps ziehen, um sie umzusortieren.
5. Optional die CLI in den Einstellungen aktivieren, wenn du dein Layout per Terminal-Skript steuern willst.

### Vollbild vs. kompakt

- **Vollbild** füllt den gesamten Bildschirm — am nächsten am ursprünglichen Launchpad.
- **Kompakt** ist ein schwebendes Fenster mit abgerundeten Ecken, das sich in der Größe anpassen lässt.
- Darstellungseinstellungen (Icon-Skalierung, Abstände, Position der Seitenanzeige u. a.) werden für jeden Modus separat gespeichert.
- Im Vollbildmodus lässt sich optional die Menüleiste ausblenden; macOS blendet dabei automatisch auch das Dock aus.

## Wichtige Einstellungen

- **Darstellung**: Icon-Skalierung, Beschriftungsgröße und -sichtbarkeit, Grid-Abstände — mit eigenen Werten für Ordnerinhalte — sowie ein Hintergrundstil (Weichzeichnung, natives Liquid Glass oder ein vom Live-Hintergrundbild abgeleiteter Hintergrund)
- **Suche**: Umschalter für unscharfe Suche und Debounce-Zeit der Suche
- **Ausgeblendete Apps**: bestimmte Apps aus dem Grid heraushalten, ohne sie zu deinstallieren
- **Backup**: Ordner wählen, zeitgestempelte Backups erstellen, alte aus einer Liste wiederherstellen oder löschen
- **Shortcut & Gesten**: der globale Shortcut, Hot Corner und (experimentelle) Trackpad-Gesten-Zuordnungen
- **Updates**: Umschalter für automatische Prüfung und manueller „Nach Updates suchen"-Button, beide über Sparkle

## Problembehandlung

**Die App startet nicht.** Prüfe, ob macOS 26.0 oder neuer läuft und ob das Quarantäne-Flag entfernt wurde (siehe oben).

**„Nach Updates suchen" meldet einen Fehler.** LaunchNG nutzt Sparkle mit einem signierten Update-Feed; eine manuelle Prüfung sollte innerhalb weniger Minuten stets die zuletzt veröffentlichte Version widerspiegeln.

**Der Terminal-Befehl `launchng` fehlt.** Das ist optional — aktiviere zuerst die Kommandozeilenschnittstelle in den Einstellungen, LaunchNG installiert (und kann später wieder entfernen) den verwalteten Befehl selbst.

## Mitwirken

1. Repository forken
2. Feature-Branch erstellen (`git checkout -b feature/dein-feature`)
3. Änderungen mit klarer Beschreibung committen
4. Branch pushen und Pull Request öffnen

Ein paar Dinge, die den Review erleichtern:
- Rein signaturbezogene Xcode-Projektänderungen aus dem Diff heraushalten (siehe lokale Code-Signierung oben)
- Wer am Core-Animation-Grid arbeitet, sollte zuerst `GridReorderPlan.swift` prüfen — Umsortier-/Paging-Logik gehört dorthin statt pro View dupliziert zu werden
- Vor dem Öffnen einer PR die Testsuite laufen lassen:
  ```bash
  xcodebuild test -scheme LaunchNG -destination 'platform=macOS'
  ```

Aktuelle, echte Screenshots (Haupt-Grid, ein paar Einstellungs-Tabs) sind ebenfalls ein sehr willkommener Beitrag — siehe den Platzhalter am Anfang dieser Datei.

### Weiterführende Dokumentation

- [Folder Liquid Glass](../Documentation/FolderLiquidGlass.md) — Design-Constraints hinter den gläsernen Ordnersymbolen, was bereits verifiziert ist und was noch eine Abnahme braucht
- [Grid diagnostics](../scripts/diagnostics/README.md) — manuelle Prüfwerkzeuge für Grid und Glas-Overlay, mit genauer Abdeckung und ihren Grenzen

## Lizenz und Namensnennung

LaunchNG ist ein Fork von [LaunchNext](https://github.com/RoversX/LaunchNext) von RoversX, das seinerseits auf eine breitere Community-Initiative für Launchpad-Ersatz zurückgeht. Beide Projekte stehen unter der GPL-3.0-Lizenz, und LaunchNG folgt denselben Bedingungen — siehe [LICENSE](../LICENSE).

Die experimentelle Trackpad-Gesten-Unterstützung basiert auf [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) und dem Fork von [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport).

---

![GitHub downloads](https://img.shields.io/github/downloads/moonmig/LaunchNG/total)
