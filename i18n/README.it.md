# LaunchNG

**Lingue**: [English](../README.md) | [简体中文](README.zh.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

macOS Tahoe (26) ha eliminato Launchpad del tutto. LaunchNG lo riporta come app nativa: al primo avvio legge il tuo layout Launchpad esistente direttamente dal database di macOS, poi reimplementa paginazione, cartelle, ricerca e riordino tramite trascinamento sopra una griglia renderizzata con Core Animation, con integrazione nel Dock, una CLI/TUI inclusa e aggiornamenti automatici firmati direttamente nell'app.

## Scarica

**[Ottieni l'ultima versione](https://github.com/moonmig/LaunchNG/releases/latest)**

Se lo trovi utile, una stella sul repository è molto apprezzata. LaunchNG è nato come fork di [LaunchNext](https://github.com/RoversX/LaunchNext) di RoversX — anche il progetto originale merita una stella.

<!-- Gli screenshot andranno qui — vedi la sezione Contribuire se vuoi inviarne di aggiornati. -->

### Se macOS blocca l'avvio dell'app

Le release sono build non firmate/ad-hoc (questo fork non usa un account sviluppatore Apple a pagamento), quindi Gatekeeper rifiuterà di aprire l'app finché non rimuovi una volta il flag di quarantena:

```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNG.app
```

Esegui questo comando solo su app di cui ti fidi davvero — disattiva il controllo di quarantena dei download di macOS per quell'app.

Stai compilando dal sorgente? Vedi [Configurare la firma del codice locale](#configure-local-code-signing) più sotto; non ti servirà questo comando.

## Cosa offre LaunchNG

- **Importazione con un clic dal vero database di Launchpad** — legge direttamente `/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db` e ricostruisce esattamente le tue cartelle, posizioni e pagine esistenti
- **La classica esperienza a griglia paginata** — ricerca, navigazione da tastiera, riordino per trascinamento, creazione di cartelle trascinando un'icona su un'altra
- **Rendering interamente basato su Core Animation**, incluso il trascinamento diretto nel Dock e le icone di cartella Liquid Glass native su macOS 26
- **Layout delle cartelle**: paginato (come l'originale) o scorrimento verticale, a tua scelta
- **Ricerca fuzzy** con corrispondenza di traslitterazione CJK (pinyin, ecc.), così anche un input parziale o impreciso trova comunque l'app giusta
- **Attivazione tramite angolo attivo e gesti del trackpad**, incluso il supporto sperimentale per pizzico e tap a 4/5 dita
- **Una CLI e una TUI** per ispezionare o gestire via script il tuo layout dal terminale
- **Aggiornamenti automatici firmati** tramite [Sparkle](https://sparkle-project.org), con un normale pulsante "Controlla aggiornamenti" nell'app
- **Backup locali** in una cartella a tua scelta, con una cronologia gestita da cui ripristinare
- **Nascondi le etichette delle icone, ridimensiona le icone, regola la spaziatura** — in modo indipendente per la griglia principale e per il contenuto delle cartelle
- **13 lingue** con traduzione completa dell'interfaccia (vedi l'elenco delle lingue sopra)
- **Menu contestuali potenziati** — mostra nel Finder, copia il percorso dell'app, rinomina cartelle e (opzionale) una scorciatoia per rimuovere la quarantena Gatekeeper da altre app di cui ti fidi
- **Supporto controller e feedback vocale** per configurazioni orientate all'accessibilità

## Cosa ha tolto macOS Tahoe

- Nessuna cartella creata dall'utente né organizzazione personalizzata
- Nessun riordino tramite trascinamento
- Nessuna gestione visiva delle app — solo una griglia generata automaticamente, ordinata alfabeticamente, che non si può toccare

LaunchNG esiste perché questo è un vero passo indietro, non un'impostazione predefinita ragionevole.

## Dove vivono i tuoi dati

Layout, preferenze e cache di LaunchNG risiedono in:

```
~/Library/Application Support/LaunchNG/Data.store
```

Non viene inviato nulla da nessuna parte. L'unica attività di rete è il controllo del feed di aggiornamento e, quando scegli di importarlo, la lettura del database Launchpad di Apple stesso in:

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Installazione

### Requisiti

- macOS 26 (Tahoe) o successivo
- Apple Silicon o Intel
- Xcode 26, se compili dal sorgente

### Compilare dal sorgente

```bash
git clone https://github.com/moonmig/LaunchNG.git
cd LaunchNG
open LaunchNG.xcodeproj
```

<a name="configure-local-code-signing"></a>**Configurare la firma del codice locale** (non serve un account sviluppatore Apple a pagamento):

- Seleziona il target **LaunchNG** → **Signing & Capabilities** → imposta **Team** su `None`, certificato su `Sign to Run Locally`. Lascia Hardened Runtime attivo.
- Xcode segnerà il file di progetto come modificato dopo questa operazione — non includere modifiche relative solo alla firma in una pull request.

Per eseguire con `⌘R`, la destinazione deve essere **My Mac** — una destinazione universale/"Any Mac" può compilare e archiviare, ma non può essere avviata per il debug. `⌘B` solo per compilare.

### Compilazione da riga di comando

```bash
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release

# Binario universale (Apple Silicon + Intel):
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Come si usa

1. **Al primo avvio** vengono scansionate automaticamente le applicazioni installate.
2. **Impostazioni → General → Import System Launchpad** importa il tuo layout, le cartelle e le posizioni esistenti con un clic.
3. Clic per selezionare, doppio clic (o Invio) per avviare; digita ovunque per cercare all'istante.
4. Trascina un'app su un'altra per creare una cartella; trascina le app per riordinarle.
5. Attiva facoltativamente la CLI nelle Impostazioni se vuoi gestire il layout via script dal terminale.

### Schermo intero vs. compatto

- **Schermo intero** occupa tutto lo schermo, il più vicino al Launchpad originale.
- **Compatto** è una finestra flottante con angoli arrotondati, ridimensionabile.
- Le impostazioni di aspetto (scala delle icone, spaziatura, posizione dell'indicatore di pagina, ecc.) sono tenute separate per ciascuna modalità.
- Lo schermo intero può nascondere facoltativamente la barra dei menu; macOS nasconde automaticamente anche il Dock quando è attivo.

## Impostazioni degne di nota

- **Aspetto**: scala delle icone, dimensione e visibilità delle etichette, spaziatura della griglia — con valori separati per il contenuto delle cartelle — più uno stile di sfondo (sfocatura, Liquid Glass nativo, o uno sfondo derivato dallo sfondo dinamico)
- **Ricerca**: interruttore per la corrispondenza fuzzy e tempo di debounce della ricerca
- **App nascoste**: tieni fuori dalla griglia app specifiche senza disinstallarle
- **Backup**: scegli una cartella, crea backup con timestamp, ripristina o elimina quelli vecchi da un elenco
- **Scorciatoia e gesti**: la scorciatoia globale, l'angolo attivo e le associazioni dei gesti del trackpad (sperimentali)
- **Aggiornamenti**: interruttore per il controllo automatico e pulsante manuale "Controlla aggiornamenti", entrambi basati su Sparkle

## Risoluzione dei problemi

**L'app non si avvia.** Verifica di avere macOS 26.0 o successivo e che il flag di quarantena sia stato rimosso (vedi sopra).

**"Controlla aggiornamenti" segnala un problema.** LaunchNG usa Sparkle con un feed di aggiornamento firmato; un controllo manuale dovrebbe sempre riflettere l'ultima release pubblicata entro pochi minuti.

**Il comando `launchng` non c'è nel terminale.** È opzionale — attiva prima l'interfaccia a riga di comando nelle Impostazioni, e LaunchNG installerà (e in seguito potrà rimuovere) da solo il comando gestito.

## Contribuire

1. Fai un fork del repository
2. Crea un branch per la funzionalità (`git checkout -b feature/tua-funzionalita`)
3. Fai il commit delle modifiche con un messaggio chiaro
4. Fai il push del branch e apri una pull request

Alcune cose che aiutano la revisione a procedere senza intoppi:
- Tieni fuori dal diff le modifiche al progetto Xcode relative solo alla firma (vedi la firma del codice locale sopra)
- Se tocchi la griglia Core Animation, controlla prima `GridReorderPlan.swift` — la logica di riordino/paginazione deve stare lì, non essere duplicata per ogni vista
- Esegui la suite di test prima di aprire una PR:
  ```bash
  xcodebuild test -scheme LaunchNG -destination 'platform=macOS'
  ```

Anche screenshot aggiornati e accurati (griglia principale, un paio di schede delle Impostazioni) sono un contributo davvero utile — vedi il placeholder all'inizio di questo file.

### Ulteriore documentazione

- [Folder Liquid Glass](../Documentation/FolderLiquidGlass.md) — vincoli di design dietro le icone di cartella in vetro, cosa è verificato e cosa richiede ancora un'accettazione finale
- [Grid diagnostics](../scripts/diagnostics/README.md) — sonde manuali per la griglia e l'overlay in vetro, con la loro copertura e i limiti esatti

## Licenza e attribuzione

LaunchNG è un fork di [LaunchNext](https://github.com/RoversX/LaunchNext) di RoversX, che a sua volta risale a uno sforzo comunitario più ampio per sostituire Launchpad. Entrambi i progetti sono sotto licenza GPL-3.0, e LaunchNG segue gli stessi termini — vedi [LICENSE](../LICENSE).

Il supporto sperimentale ai gesti del trackpad è basato su [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) e sul fork di [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport).

---

![GitHub downloads](https://img.shields.io/github/downloads/moonmig/LaunchNG/total)
