# LaunchNG

**Jazyky**: [English](../README.md) | [简体中文](README.zh.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

macOS Tahoe (26) zcela odstranil Launchpad. LaunchNG ho vrací zpět jako nativní aplikaci: při prvním spuštění načte vaše stávající rozvržení Launchpadu přímo z vlastní databáze macOS a poté sám implementuje stránkování, složky, vyhledávání a přeuspořádávání přetažením nad mřížkou vykreslovanou pomocí Core Animation, s integrací do Docku, přiloženým CLI/TUI a podepsaným automatickým aktualizátorem přímo v aplikaci.

## Stáhnout

**[Získat nejnovější verzi](https://github.com/moonmig/LaunchNG/releases/latest)**

Pokud vám aplikace přijde užitečná, oceníme hvězdičku na repozitáři. LaunchNG vznikl jako fork [LaunchNext](https://github.com/RoversX/LaunchNext) od RoversX — i původní projekt si hvězdičku zaslouží.

<!-- Zde budou screenshoty — pokud chcete přispět aktuálními, podívejte se do sekce Přispívání. -->

### Pokud macOS blokuje spuštění aplikace

Vydání jsou nepodepsané/ad-hoc buildy (tento fork nepoužívá placený Apple Developer účet), takže Gatekeeper odmítne aplikaci otevřít, dokud jednou neodstraníte příznak karantény:

```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNG.app
```

Tento příkaz spouštějte jen u aplikací, kterým skutečně důvěřujete — vypíná pro danou aplikaci kontrolu karantény stažených souborů v macOS.

Sestavujete ze zdrojového kódu? Podívejte se níže na [Nastavení lokálního podepisování kódu](#configure-local-code-signing); tento příkaz nebudete potřebovat.

## Co LaunchNG nabízí

- **Import na jedno kliknutí z reálné databáze Launchpadu** — přímo čte `/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db` a přesně obnoví vaše stávající složky, pozice a stránky
- **Klasický zážitek stránkované mřížky** — vyhledávání, navigace klávesnicí, přeuspořádávání přetažením, vytváření složek přetažením jedné ikony na druhou
- **Vykreslování skrz naskrz pomocí Core Animation**, včetně přetahování přímo do Docku a nativních ikon složek Liquid Glass na macOS 26
- **Rozvržení složek**: stránkované (jako originál) nebo svislé posouvání, podle vaší preference
- **Fuzzy vyhledávání** s CJK (pchin-jin/romanizace) shodou, takže i částečný nebo nepřesný vstup najde správnou aplikaci
- **Aktivace aktivním rohem a gesty trackpadu**, včetně experimentální podpory sevření a poklepání 4/5 prsty
- **CLI a TUI** pro kontrolu nebo skriptování rozvržení z terminálu
- **Podepsané automatické aktualizace** přes [Sparkle](https://sparkle-project.org), s běžným tlačítkem „Zkontrolovat aktualizace" v aplikaci
- **Lokální zálohy** do vámi zvolené složky, se spravovanou historií, ze které lze obnovit
- **Skrytí popisků ikon aplikací, změna velikosti ikon, úprava rozestupů** — nezávisle pro hlavní mřížku a pro obsah složek
- **13 jazyků** s kompletním překladem uživatelského rozhraní (viz seznam jazyků výše)
- **Rozšířené kontextové nabídky** — zobrazit ve Finderu, kopírovat cestu k aplikaci, přejmenovat složky a (volitelně) zkratka pro odstranění karantény Gatekeeperu u jiných důvěryhodných aplikací
- **Podpora ovladače a hlasové zpětné vazby** pro konfigurace zaměřené na přístupnost

## Co macOS Tahoe vzal

- Žádné uživatelem vytvořené složky ani vlastní organizace
- Žádné přeuspořádávání přetažením
- Vůbec žádná vizuální správa aplikací — jen automaticky generovaná, abecedně seřazená mřížka, na kterou nelze sáhnout

LaunchNG existuje proto, že jde o skutečný krok zpět, ne o rozumné výchozí chování.

## Kde žijí vaše data

Vlastní rozvržení, předvolby a cache LaunchNG žijí v:

```
~/Library/Application Support/LaunchNG/Data.store
```

Nikam se nic neodesílá. Jedinou síťovou aktivitou je kontrola feedu aktualizací a — pokud se rozhodnete pro import — čtení vlastní databáze Launchpadu od Applu na:

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Instalace

### Požadavky

- macOS 26 (Tahoe) nebo novější
- Apple Silicon nebo Intel
- Xcode 26, pokud sestavujete ze zdrojového kódu

### Sestavení ze zdrojového kódu

```bash
git clone https://github.com/moonmig/LaunchNG.git
cd LaunchNG
open LaunchNG.xcodeproj
```

<a name="configure-local-code-signing"></a>**Nastavení lokálního podepisování kódu** (není potřeba placený Apple Developer účet):

- Vyberte target **LaunchNG** → **Signing & Capabilities** → nastavte **Team** na `None`, certifikát na `Sign to Run Locally`. Hardened Runtime nechte zapnutý.
- Xcode poté označí soubor projektu jako změněný — tyto změny týkající se pouze podepisování do pull requestu nezahrnujte.

Pro spuštění pomocí `⌘R` musí být cílem **My Mac** — univerzální cíl/„Any Mac" lze sestavit a archivovat, ale nelze ho spustit pro ladění. `⌘B` jen pro sestavení.

### Sestavení z příkazové řádky

```bash
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release

# Univerzální binárka (Apple Silicon + Intel):
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Používání

1. **Při prvním spuštění** se automaticky naskenují vaše nainstalované aplikace.
2. **Nastavení → General → Import System Launchpad** jedním kliknutím naimportuje vaše stávající rozvržení, složky a pozice.
3. Klikněte pro výběr, dvojklik (nebo Return) pro spuštění; pište kdekoliv pro okamžité vyhledávání.
4. Přetáhněte jednu aplikaci na druhou pro vytvoření složky; přetahujte aplikace pro jejich přeuspořádání.
5. Volitelně povolte CLI v Nastavení, pokud chcete rozvržení skriptovat z terminálu.

### Celá obrazovka vs. kompaktní

- **Celá obrazovka** pokrývá celou obrazovku, nejblíže originálnímu Launchpadu.
- **Kompaktní** je plovoucí okno se zaoblenými rohy, které lze měnit velikost.
- Nastavení vzhledu (měřítko ikon, rozestupy, pozice indikátoru stránky a další) se sledují odděleně pro každý režim.
- Celá obrazovka může volitelně skrýt panel nabídek; macOS při tom automaticky skryje i Dock.

## Pozoruhodná nastavení

- **Vzhled**: měřítko ikon, velikost a viditelnost popisků, rozestupy mřížky — s odděleným nastavením pro obsah složek — plus styl pozadí (rozmazání, nativní Liquid Glass, nebo pozadí odvozené z živé plochy)
- **Vyhledávání**: přepínač fuzzy shody a doba zpoždění vyhledávání
- **Skryté aplikace**: udržujte konkrétní aplikace mimo mřížku, aniž byste je odinstalovali
- **Záloha**: vyberte složku, vytvářejte zálohy s časovým razítkem, obnovujte nebo mažte staré ze seznamu
- **Zkratka a gesta**: globální zkratka, aktivní roh a (experimentální) vazby gest trackpadu
- **Aktualizace**: přepínač automatické kontroly a ruční tlačítko „Zkontrolovat aktualizace", obojí postavené na Sparkle

## Řešení problémů

**Aplikace se nespustí.** Ověřte, že máte macOS 26.0 nebo novější a že byl odstraněn příznak karantény (viz výše).

**„Zkontrolovat aktualizace" hlásí problém.** LaunchNG používá Sparkle s podepsaným feedem aktualizací; ruční kontrola by měla vždy během několika minut odrážet nejnovější vydanou verzi.

**Terminálový příkaz `launchng` chybí.** Je volitelný — nejprve povolte rozhraní příkazové řádky v Nastavení a LaunchNG si sám nainstaluje (a později může i odstranit) spravovaný shim.

## Přispívání

1. Forkněte repozitář
2. Vytvořte feature branch (`git checkout -b feature/vase-funkce`)
3. Commitněte změny s jasnou zprávou
4. Pushněte branch a otevřete pull request

Několik věcí, které pomohou hladkému průběhu revize:
- Nezahrnujte do diffu změny Xcode projektu týkající se pouze podepisování (viz lokální podepisování kódu výše)
- Pokud upravujete mřížku Core Animation, nejprve zkontrolujte `GridReorderPlan.swift` — logika přeuspořádávání/stránkování patří tam, ne duplikovaná v jednotlivých pohledech
- Před otevřením PR spusťte testovací sadu:
  ```bash
  xcodebuild test -scheme LaunchNG -destination 'platform=macOS'
  ```

Aktuální a přesné screenshoty (hlavní mřížka, pár záložek Nastavení) jsou také opravdu užitečným příspěvkem — viz zástupný symbol na začátku tohoto souboru.

### Další dokumentace

- [Folder Liquid Glass](../Documentation/FolderLiquidGlass.md) — designová omezení za skleněnými ikonami složek, co je ověřeno a co ještě potřebuje akceptační testování
- [Grid diagnostics](../scripts/diagnostics/README.md) — manuální sondy pro mřížku a skleněný overlay, s jejich přesným pokrytím a limity

## Licence a atribuce

LaunchNG je fork [LaunchNext](https://github.com/RoversX/LaunchNext) od RoversX, který sám sahá zpět k širší komunitní snaze o náhradu Launchpadu. Oba projekty jsou licencovány pod GPL-3.0 a LaunchNG dodržuje stejné podmínky — viz [LICENSE](../LICENSE).

Experimentální podpora gest trackpadu je postavena na [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) a forku od [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport).

---

![GitHub downloads](https://img.shields.io/github/downloads/moonmig/LaunchNG/total)
