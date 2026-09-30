# LaunchNG

**Idiomas**: [English](../README.md) | [简体中文](README.zh.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

macOS Tahoe (26) eliminó Launchpad por completo. LaunchNG lo trae de vuelta como una aplicación nativa: en el primer arranque lee tu diseño de Launchpad existente directamente desde la propia base de datos de macOS, y luego reimplementa la paginación, las carpetas, la búsqueda y la reordenación por arrastrar y soltar sobre una cuadrícula renderizada con Core Animation, con integración con el Dock, un CLI/TUI incluido y actualizaciones automáticas firmadas dentro de la propia aplicación.

## Descargar

**[Obtener la última versión](https://github.com/moonmig/LaunchNG/releases/latest)**

Si te resulta útil, una estrella en el repositorio es muy apreciada. LaunchNG comenzó como un fork de [LaunchNext](https://github.com/RoversX/LaunchNext) de RoversX — el proyecto original también merece una estrella.

<!-- Las capturas de pantalla irán aquí — consulta la sección Contribuir si quieres enviar unas actuales. -->

### Si macOS bloquea la aplicación al abrirla

Las versiones publicadas son builds sin firmar/ad-hoc (este fork no usa una cuenta de desarrollador de Apple de pago), por lo que Gatekeeper se negará a abrir la aplicación hasta que elimines una vez la marca de cuarentena:

```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNG.app
```

Ejecuta este comando solo con aplicaciones en las que realmente confíes — desactiva la comprobación de cuarentena de descargas de macOS para esa aplicación.

¿Vas a compilar desde el código fuente? Consulta [Configurar la firma de código local](#configure-local-code-signing) más abajo; no necesitarás este comando.

## Qué ofrece LaunchNG

- **Importación con un clic desde la base de datos real de Launchpad** — lee directamente `/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db` y reconstruye exactamente tus carpetas, posiciones y páginas existentes
- **La clásica experiencia de cuadrícula paginada** — búsqueda, navegación por teclado, reordenación por arrastrar y soltar, creación de carpetas arrastrando un icono sobre otro
- **Renderizado íntegramente con Core Animation**, incluyendo arrastrar y soltar directamente en el Dock e iconos de carpeta Liquid Glass nativos en macOS 26
- **Disposiciones de carpeta**: paginada (como la original) o desplazamiento vertical, como prefieras
- **Búsqueda difusa** con coincidencia de transliteración CJK (pinyin, etc.), de modo que una entrada parcial o imperfecta igualmente encuentre la aplicación correcta
- **Activación por esquina activa y gestos de trackpad**, incluido el soporte experimental de pellizco y toque con 4/5 dedos
- **Un CLI y un TUI** para inspeccionar o gestionar tu disposición desde la terminal
- **Actualizaciones automáticas firmadas** mediante [Sparkle](https://sparkle-project.org), con un botón normal de «Buscar actualizaciones» dentro de la aplicación
- **Copias de seguridad locales** en la carpeta que elijas, con un historial gestionado desde el que restaurar
- **Ocultar etiquetas de iconos, redimensionar iconos, ajustar el espaciado** — de forma independiente para la cuadrícula principal y para el contenido de las carpetas
- **13 idiomas** con traducción completa de la interfaz (ver la lista de idiomas arriba)
- **Menús contextuales mejorados** — mostrar en Finder, copiar la ruta de la aplicación, renombrar carpetas y (opcional) un atajo para quitar la cuarentena de Gatekeeper a otras aplicaciones en las que confíes
- **Soporte de mando y retroalimentación por voz** para configuraciones centradas en la accesibilidad

## Lo que macOS Tahoe se llevó

- Sin carpetas creadas por el usuario ni organización personalizada
- Sin reordenación por arrastrar y soltar
- Sin gestión visual de aplicaciones en absoluto — solo una cuadrícula generada automáticamente, ordenada alfabéticamente, que no puedes tocar

LaunchNG existe porque eso es un retroceso real, no una opción por defecto razonable.

## Dónde viven tus datos

El diseño, las preferencias y la caché propios de LaunchNG residen en:

```
~/Library/Application Support/LaunchNG/Data.store
```

Nada se envía a ningún sitio. La única actividad de red es comprobar el feed de actualizaciones y, cuando eliges importarla, leer la propia base de datos de Launchpad de Apple en:

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Instalación

### Requisitos

- macOS 26 (Tahoe) o posterior
- Apple Silicon o Intel
- Xcode 26, si compilas desde el código fuente

### Compilar desde el código fuente

```bash
git clone https://github.com/moonmig/LaunchNG.git
cd LaunchNG
open LaunchNG.xcodeproj
```

<a name="configure-local-code-signing"></a>**Configurar la firma de código local** (no se necesita cuenta de desarrollador de Apple de pago):

- Selecciona el target **LaunchNG** → **Signing & Capabilities** → pon **Team** en `None` y el certificado de firma en `Sign to Run Locally`. Deja Hardened Runtime activado.
- Xcode marcará el archivo del proyecto como modificado después de esto — no incluyas cambios relacionados solo con la firma en un pull request.

Para ejecutar con `⌘R`, el destino debe ser **My Mac** — un destino universal/«Any Mac» puede compilar y archivar, pero no puede ejecutarse para depuración. `⌘B` solo para compilar.

### Compilación por línea de comandos

```bash
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release

# Binario universal (Apple Silicon + Intel):
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Cómo usarlo

1. **En el primer arranque** se escanean automáticamente tus aplicaciones instaladas.
2. **Ajustes → General → Import System Launchpad** trae tu diseño, carpetas y posiciones existentes con un clic.
3. Haz clic para seleccionar, doble clic (o Intro) para abrir; escribe en cualquier momento para buscar.
4. Arrastra una aplicación sobre otra para crear una carpeta; arrastra aplicaciones para reordenarlas.
5. Activa opcionalmente el CLI en Ajustes si quieres gestionar tu disposición mediante scripts desde la terminal.

### Pantalla completa vs. compacto

- **Pantalla completa** cubre toda la pantalla, lo más parecido al Launchpad original.
- **Compacto** es una ventana flotante con esquinas redondeadas que puedes redimensionar.
- Los ajustes de apariencia (escala de iconos, espaciado, posición del indicador de páginas, etc.) se guardan por separado para cada modo.
- Pantalla completa puede ocultar opcionalmente la barra de menús; macOS oculta el Dock automáticamente cuando eso está activado.

## Ajustes destacados

- **Apariencia**: escala de iconos, tamaño y visibilidad de etiquetas, espaciado de la cuadrícula — con valores independientes para el contenido de las carpetas — además de un estilo de fondo (desenfoque, Liquid Glass nativo, o un fondo derivado del fondo de pantalla en vivo)
- **Búsqueda**: interruptor de coincidencia difusa y tiempo de debounce de búsqueda
- **Aplicaciones ocultas**: mantén ciertas aplicaciones fuera de la cuadrícula sin desinstalarlas
- **Copia de seguridad**: elige una carpeta, crea copias con marca de tiempo, restaura o elimina las antiguas desde una lista
- **Atajo y gestos**: el atajo global, la esquina activa, y las asignaciones de gestos del trackpad (experimentales)
- **Actualizaciones**: interruptor de comprobación automática y botón manual de «Buscar actualizaciones», ambos respaldados por Sparkle

## Solución de problemas

**La aplicación no arranca.** Confirma que tienes macOS 26.0 o posterior y que la marca de cuarentena se ha eliminado (ver arriba).

**«Buscar actualizaciones» indica que algo va mal.** LaunchNG usa Sparkle con un feed de actualizaciones firmado; una comprobación manual siempre debería reflejar la última versión publicada en cuestión de minutos.

**El comando `launchng` no aparece en la terminal.** Es opcional — activa primero la interfaz de línea de comandos en Ajustes, y LaunchNG instalará (y más tarde podrá eliminar) el shim gestionado por sí mismo.

## Contribuir

1. Haz un fork del repositorio
2. Crea una rama de funcionalidad (`git checkout -b feature/tu-funcionalidad`)
3. Confirma tus cambios con un mensaje claro
4. Sube la rama y abre un pull request

Algunas cosas que ayudan a que la revisión vaya bien:
- Mantén fuera de tu diff los cambios de proyecto Xcode relacionados solo con la firma (ver firma de código local arriba)
- Si tocas la cuadrícula de Core Animation, revisa primero `GridReorderPlan.swift` — la lógica de reordenación/paginación debe vivir ahí, no duplicarse por vista
- Ejecuta la suite de pruebas antes de abrir una PR:
  ```bash
  xcodebuild test -scheme LaunchNG -destination 'platform=macOS'
  ```

Unas capturas de pantalla frescas y actuales (la cuadrícula principal, un par de pestañas de Ajustes) también son una contribución realmente útil — mira el marcador de posición cerca del principio de este archivo.

### Documentación adicional

- [Folder Liquid Glass](../Documentation/FolderLiquidGlass.md) — restricciones de diseño detrás de los iconos de cristal de las carpetas, qué está verificado y qué aún necesita aceptación
- [Grid diagnostics](../scripts/diagnostics/README.md) — sondas manuales para la cuadrícula y la superposición de cristal, con su cobertura y límites exactos

## Licencia y atribución

LaunchNG es un fork de [LaunchNext](https://github.com/RoversX/LaunchNext) de RoversX, que a su vez se remonta a un esfuerzo comunitario más amplio de reemplazo de Launchpad. Ambos proyectos tienen licencia GPL-3.0, y LaunchNG sigue los mismos términos — ver [LICENSE](../LICENSE).

El soporte experimental de gestos de trackpad se basa en [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) y el fork de [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport).

---

![GitHub downloads](https://img.shields.io/github/downloads/moonmig/LaunchNG/total)
