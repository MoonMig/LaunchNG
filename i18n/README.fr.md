# LaunchNG

**Langues**: [English](../README.md) | [简体中文](README.zh.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

macOS Tahoe (26) a purement et simplement supprimé Launchpad. LaunchNG le fait revenir sous forme d'application native : au premier lancement, il lit votre disposition Launchpad existante directement depuis la base de données de macOS, puis réimplémente la pagination, les dossiers, la recherche et le glisser-déposer pour réorganiser les icônes, le tout sur une grille rendue via Core Animation, avec intégration au Dock, un CLI/TUI intégré et une mise à jour automatique signée directement dans l'application.

## Télécharger

**[Obtenir la dernière version](https://github.com/moonmig/LaunchNG/releases/latest)**

Si cette application vous est utile, une étoile sur le dépôt est appréciée. LaunchNG a débuté comme un fork de [LaunchNext](https://github.com/RoversX/LaunchNext) par RoversX — le projet original mérite aussi une étoile.

<!-- Les captures d'écran viendront ici — voir la section Contribuer si vous souhaitez en proposer d'actuelles. -->

### Si macOS bloque l'application

Les versions publiées sont des builds non signés/ad-hoc (ce fork n'utilise pas de compte développeur Apple payant), donc Gatekeeper refusera d'ouvrir l'application tant que vous n'aurez pas retiré une fois le marqueur de quarantaine :

```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNG.app
```

N'exécutez cette commande que pour des applications auxquelles vous faites réellement confiance — elle désactive la vérification de quarantaine des téléchargements de macOS pour cette application.

Vous compilez depuis les sources ? Voir [Configurer la signature de code locale](#configure-local-code-signing) ci-dessous ; cette commande ne sera pas nécessaire.

## Ce que fait LaunchNG

- **Import en un clic depuis la vraie base Launchpad** — lit directement `/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db` et reconstitue exactement vos dossiers, positions et pages existants
- **L'expérience classique de grille paginée** — recherche, navigation au clavier, réorganisation par glisser-déposer, création de dossier en glissant une icône sur une autre
- **Rendu entièrement basé sur Core Animation**, y compris le glisser-déposer directement vers le Dock et les icônes de dossier Liquid Glass natives sur macOS 26
- **Dispositions de dossier** : paginée (comme l'original) ou défilement vertical, selon votre préférence
- **Recherche floue** avec correspondance de translittération CJK (pinyin, etc.), pour retrouver l'application même avec une saisie partielle ou imparfaite
- **Activation par coin actif et gestes du trackpad**, y compris le support expérimental du pincement et du tap à 4/5 doigts
- **Un CLI et un TUI** pour inspecter ou scripter votre disposition depuis le terminal
- **Mises à jour automatiques signées** via [Sparkle](https://sparkle-project.org), avec un bouton classique « Rechercher des mises à jour » dans l'application
- **Sauvegardes locales** vers un dossier de votre choix, avec un historique géré permettant de restaurer
- **Masquer les libellés d'icônes, redimensionner les icônes, ajuster l'espacement** — indépendamment pour la grille principale et pour le contenu des dossiers
- **13 langues** avec traduction complète de l'interface (voir la liste des langues ci-dessus)
- **Menus contextuels enrichis** — afficher dans le Finder, copier le chemin de l'application, renommer les dossiers, et (en option) un raccourci pour lever la quarantaine Gatekeeper d'autres applications en qui vous avez confiance
- **Support manette et retour vocal** pour les configurations axées accessibilité

## Ce que macOS Tahoe a fait disparaître

- Plus aucun dossier créé par l'utilisateur, ni d'organisation personnalisée
- Plus de réorganisation par glisser-déposer
- Aucune gestion visuelle des applications — juste une grille générée automatiquement, triée alphabétiquement, à laquelle on ne peut pas toucher

LaunchNG existe parce qu'il s'agit là d'une vraie régression, pas d'un choix par défaut raisonnable.

## Où vivent vos données

La disposition, les préférences et le cache propres à LaunchNG résident dans :

```
~/Library/Application Support/LaunchNG/Data.store
```

Rien n'est envoyé où que ce soit. La seule activité réseau consiste à vérifier le flux de mise à jour et, lorsque vous choisissez de l'importer, à lire la propre base de données Launchpad d'Apple à :

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Installation

### Prérequis

- macOS 26 (Tahoe) ou ultérieur
- Apple Silicon ou Intel
- Xcode 26, pour compiler depuis les sources

### Compiler depuis les sources

```bash
git clone https://github.com/moonmig/LaunchNG.git
cd LaunchNG
open LaunchNG.xcodeproj
```

<a name="configure-local-code-signing"></a>**Configurer la signature de code locale** (aucun compte développeur Apple payant requis) :

- Sélectionnez la cible **LaunchNG** → **Signing & Capabilities** → réglez **Team** sur `None`, et le certificat de signature sur `Sign to Run Locally`. Laissez Hardened Runtime activé.
- Xcode marquera ensuite le fichier de projet comme modifié — n'incluez pas ces changements liés uniquement à la signature dans une pull request.

Pour lancer avec `⌘R`, la destination doit être **My Mac** — une destination universelle/« Any Mac » permet de compiler et d'archiver, mais pas de lancer en mode débogage. `⌘B` pour compiler uniquement.

### Compilation en ligne de commande

```bash
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release

# Binaire universel (Apple Silicon + Intel) :
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Utilisation

1. **Au premier lancement**, LaunchNG scanne automatiquement vos applications installées.
2. **Réglages → General → Import System Launchpad** récupère votre disposition, dossiers et positions existants en un clic.
3. Cliquez pour sélectionner, double-cliquez (ou Retour) pour lancer ; tapez n'importe où pour lancer une recherche instantanée.
4. Glissez une application sur une autre pour créer un dossier ; glissez les applications pour les réorganiser.
5. Activez le CLI dans les réglages si vous souhaitez scripter votre disposition depuis le terminal.

### Plein écran vs. compact

- **Plein écran** occupe tout l'écran, au plus proche du Launchpad d'origine.
- **Compact** est une fenêtre flottante aux coins arrondis, redimensionnable.
- Les réglages d'apparence (échelle des icônes, espacement, position de l'indicateur de page, etc.) sont conservés séparément pour chaque mode.
- Le mode plein écran peut masquer la barre de menus en option ; macOS masque alors automatiquement le Dock.

## Réglages notables

- **Apparence** : échelle des icônes, taille et visibilité des libellés, espacement de la grille — avec des valeurs distinctes pour le contenu des dossiers — plus un style de fond (flou, Liquid Glass natif, ou un fond dérivé du fond d'écran en direct)
- **Recherche** : bascule de correspondance floue et délai de debounce de la recherche
- **Applications masquées** : exclure certaines applications de la grille sans les désinstaller
- **Sauvegarde** : choisissez un dossier, créez des sauvegardes horodatées, restaurez ou supprimez les anciennes depuis une liste
- **Raccourci et gestes** : le raccourci global, le coin actif, et les liaisons de gestes du trackpad (expérimentales)
- **Mises à jour** : bascule de vérification automatique et bouton manuel « Rechercher des mises à jour », tous deux propulsés par Sparkle

## Dépannage

**L'application ne démarre pas.** Vérifiez que vous êtes sur macOS 26.0 ou ultérieur et que le marqueur de quarantaine a bien été retiré (voir ci-dessus).

**« Rechercher des mises à jour » signale un problème.** LaunchNG utilise Sparkle avec un flux de mise à jour signé ; une vérification manuelle devrait toujours refléter la dernière version publiée en l'espace de quelques minutes.

**La commande `launchng` n'existe pas dans le terminal.** C'est optionnel — activez d'abord l'interface en ligne de commande dans les réglages, et LaunchNG installera (et pourra plus tard retirer) lui-même la commande gérée.

## Contribuer

1. Forkez le dépôt
2. Créez une branche de fonctionnalité (`git checkout -b feature/votre-fonctionnalite`)
3. Committez vos changements avec un message clair
4. Poussez la branche et ouvrez une pull request

Quelques éléments qui facilitent la relecture :
- Ne pas inclure dans le diff les changements Xcode liés uniquement à la signature (voir la signature de code locale ci-dessus)
- Si vous touchez à la grille Core Animation, commencez par `GridReorderPlan.swift` — la logique de réorganisation/pagination doit y résider plutôt que d'être dupliquée par vue
- Lancez la suite de tests avant d'ouvrir une PR :
  ```bash
  xcodebuild test -scheme LaunchNG -destination 'platform=macOS'
  ```

Des captures d'écran fraîches et actuelles (grille principale, quelques onglets de réglages) sont également une contribution très utile — voir le placeholder en haut de ce fichier.

### Documentation complémentaire

- [Folder Liquid Glass](../Documentation/FolderLiquidGlass.md) — contraintes de conception derrière les icônes de dossier en verre, ce qui est vérifié, et ce qui nécessite encore une validation finale
- [Grid diagnostics](../scripts/diagnostics/README.md) — sondes manuelles pour la grille et l'overlay de verre, avec leur couverture exacte et leurs limites

## Licence et attribution

LaunchNG est un fork de [LaunchNext](https://github.com/RoversX/LaunchNext) par RoversX, qui remonte lui-même à un effort communautaire plus large de remplacement de Launchpad. Les deux projets sont sous licence GPL-3.0, et LaunchNG suit les mêmes conditions — voir [LICENSE](../LICENSE).

Le support expérimental des gestes du trackpad s'appuie sur [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) et le fork de [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport).

---

![GitHub downloads](https://img.shields.io/github/downloads/moonmig/LaunchNG/total)
