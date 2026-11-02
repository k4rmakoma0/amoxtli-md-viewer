# Amoxtli: Markdown Viewer

Visor de Markdown formateado para macOS 27. Gratuito y 100% open source (MIT). Xcode 27, Swift 6.

## Identidad

- Bundle ID: `dev.alananaya.amoxtli`
- Nombre en README/App Store: "Amoxtli: Markdown Viewer"
- `PRODUCT_NAME` y `CFBundleDisplayName`: `Amoxtli` (sin dos puntos: el nombre del .app es un nombre de archivo)
- Target/scheme: `Amoxtli`

## Reglas del proyecto

- 100% nativo: solo Foundation, SwiftUI, AppKit, UniformTypeIdentifiers. Cero dependencias de terceros, sin WKWebView.
- SwiftUI es la base. AppKit solo donde SwiftUI no alcance (ver Links), con un comentario que lo justifique.
- MVVM, async/await, sin singletons.
- Estructura: `App/`, `Domain/`, `Presentation/`, `Services/`, `Resources/`.
- Tipado fuerte, funciones pequeñas, sin duplicación, sin force unwrap, código testeable.
- No inventes APIs. Si no estás seguro de que una API exista en Xcode 27 / macOS 27, dilo y verifica contra la documentación antes de usarla.
- Errores explícitos: archivo vacío, UTF-8 inválido, archivo ilegible, bookmark obsoleto, carpeta sin markdowns (estado vacío con mensaje).

## Flujo de trabajo (Claude Code)

- Si no existe `Amoxtli.xcodeproj`, PARA y pídeme que cree en Xcode un proyecto macOS App (SwiftUI, Swift, con tests) llamado `Amoxtli` con el bundle ID de arriba. No generes el .xcodeproj a mano ni agregues herramientas externas.
- Verifica cada fase con:
  - `xcodebuild -scheme Amoxtli -destination 'platform=macOS' build`
  - `xcodebuild -scheme Amoxtli -destination 'platform=macOS' test`
- Trabaja por fases y detente al terminar cada una: debe compilar y pasar tests. No avances a la siguiente sin mi confirmación.
- Al cerrar cada fase: lista de archivos creados/modificados y qué verificaste. Sin resúmenes largos.
- Commits pequeños por fase (mensaje en inglés, imperativo).

## Fases

1. Archivo único + render
2. Links + menús contextuales
3. Carpeta + índice
4. App predeterminada

## Parsing y render

- `AttributedString(markdown:options:)` con `interpretedSyntax: .full` y `failurePolicy: .returnPartiallyParsedIfPossible`.
- Agrupar runs por `PresentationIntent` hacia un modelo propio en `Domain/`: heading(level), paragraph, orderedList, unorderedList, listItem, blockQuote, codeBlock(languageHint), table, thematicBreak. Estilos inline desde `InlinePresentationIntent`, links desde `.link`.
- Una vista SwiftUI pequeña por tipo de bloque. Tablas con `Grid`. Imágenes http(s) con `AsyncImage`.
- Code blocks: monoespaciada del sistema, fondo semántico, scroll horizontal, sin syntax highlighting.
- No asumas soporte GFM (tablas, strikethrough, task lists): verifícalo con tests y reporta qué funciona.

## Modos de apertura

1. **Un archivo** (.md/.markdown desde Finder, Open With o ⌘O): `DocumentGroup(viewing:)`. La ventana muestra SOLO contenido e índice. NO hay lista de archivos.
2. **Una carpeta** (File > Open Folder…, ⇧⌘O, `NSOpenPanel` con `canChooseDirectories`): ventana propia (`WindowGroup(for:)` con security-scoped bookmark `Data` como valor). `NavigationSplitView`: sidebar con selector segmentado Índice / Archivos, detalle con el contenido.
   - Escaneo recursivo con `FileManager`, SOLO .md y .markdown (extensión case-insensitive), agrupado por subcarpeta, omitiendo carpetas sin markdowns. Escaneo fuera del main actor. Orden alfabético localizado.
   - Restauración de ventanas con el bookmark.

3. **Sin nada que abrir** (inicio o clic en el Dock sin ventanas): ventana de bienvenida (`Window`, `.defaultLaunchBehavior(.presented)`) con Abrir archivo… y Abrir carpeta…. Reemplaza el panel de inicio del sistema (`applicationShouldOpenUntitledFile` → `false`), que solo elige archivos. Se cierra al abrir algo.
- Botón Abrir en el toolbar de ambas ventanas: clic abre archivo, su menú también ofrece carpeta.

## Índice (TOC)

- Generado desde los headings del modelo, indentado por nivel, con ids únicos aunque se repitan títulos.
- Sidebar izquierdo de `NavigationSplitView` en ambos modos (`ReaderSplitView`). En modo archivo solo muestra el índice; en modo carpeta, un `Picker` segmentado alterna entre índice y lista de archivos. Ocultable con el botón de sidebar del sistema y ⌃⌘S; visibilidad y pestaña persistidas con `@SceneStorage`. Cada segmento tiene tooltip (`.help`), y Visualización > Mostrar índice (⌥⌘1) / Mostrar archivos (⌥⌘2) muestran el sidebar en esa pestaña.

## Estadísticas de lectura

- `ReadingStats` en `Domain/`: palabras de headings, párrafos, listas, citas y tablas (sin código ni imágenes), con límites de palabra del sistema. Tiempo a 200 palabras/min; menos de 200 palabras → "menos de 1 min".
- Se muestran en un `safeAreaBar` inferior, alineado a la derecha, texto secundario.
- Click en una entrada: scroll animado al heading (`ScrollViewReader`). Respeta Reduce Motion.

## Links

- Clasificador (enum en `Domain/`): http/https y mailto → sistema; ancla `#x` → scroll al heading; cualquier otro esquema → ignorar y avisar con un indicador discreto, nunca abrir en silencio.
- Hover sobre un link: cursor `pointingHand` y pill en la esquina inferior izquierda con la URL completa (truncada al medio), estilo status bar de Safari. Desaparece al salir.
- Menú contextual sobre un link:
  - Abrir en navegador predeterminado (resolver con `NSWorkspace.shared.urlForApplication(toOpen:)` y mostrar su nombre)
  - Abrir con ▸ submenú con las apps de `NSWorkspace.shared.urlsForApplications(toOpen:)`, con icono (`NSWorkspace.shared.icon(forFile:)`) y nombre; la predeterminada marcada; abrir con `NSWorkspace.shared.open(_:withApplicationAt:configuration:)`
  - Copiar enlace
- Menú contextual sobre texto seleccionado: Copiar, Seleccionar todo. No incluir Pegar (visor de solo lectura).
- **Decision gate:** antes de implementar, haz un spike mínimo y verifica si SwiftUI `Text` expone hover por link y menú contextual por link. Si NO, renderiza los bloques de texto con un `NSViewRepresentable` sobre una subclase de `NSTextView` (`isEditable = false`, `isSelectable = true`): hover con `NSTrackingArea` + `mouseMoved` + `characterIndexForInsertion(at:)` leyendo el atributo `.link`, y menú con override de `menu(for:)`. Documenta en el README qué camino tomaste y por qué.

## App predeterminada para Markdown

- Info.plist: `UTImportedTypeDeclarations` para `net.daringfireball.markdown` (extensiones md, markdown; conforma a `public.plain-text`) y `CFBundleDocumentTypes` con rol Viewer.
- Al iniciar: si la app NO es la predeterminada (comparar `NSWorkspace.shared.urlForApplication(toOpen:)` con `Bundle.main.bundleURL`), mostrar alert propio "Usar Amoxtli para abrir archivos Markdown" con [Establecer como predeterminada] [Ahora no] y checkbox "No volver a preguntar" (UserDefaults).
- Al aceptar: `NSWorkspace.shared.setDefaultApplication(at:toOpen:)` (async throws) para el UTType de Markdown. El sistema muestra su propia confirmación; maneja error y cancelación sin crashear.
- Menú de la app: "Establecer como visor Markdown predeterminado…" siempre disponible.
- Encapsula `NSWorkspace` detrás de un protocolo mínimo (`WorkspaceServicing`) solo para testear.

## Diseño nativo (macOS 27 / Liquid Glass)

- Componentes del sistema (toolbar, `NavigationSplitView`, menús, alerts) para heredar Liquid Glass automáticamente. Prohibido simular glass con Material/blur propios en el chrome.
- El contenido NO es glass. El pill de URL y cualquier control flotante propio usan `glassEffect` dentro de `GlassEffectContainer`, con fallback sólido cuando `accessibilityReduceTransparency` esté activo.
- Toolbar estándar, `ToolbarSpacer` para agrupar. Sin title bar custom.
- Fuentes del sistema, colores semánticos, SF Symbols, accent color del usuario, light/dark automático.
- Ancho de lectura máx. ~800 pt centrado, padding generoso.
- Accesibilidad: VoiceOver (labels en TOC, links y lista de archivos), Reduce Transparency, Reduce Motion, Increase Contrast. Todo operable por teclado.

## Sandbox / seguridad

- App Sandbox con `com.apple.security.files.user-selected.read-only` y `com.apple.security.files.bookmarks.app-scope`. `com.apple.security.network.client` solo por imágenes remotas.
- Sin telemetría. Validar todo input.

## Tests (XCTest)

- `MarkdownDocument`: UTF-8 válido, vacío, bytes inválidos, archivo grande.
- Parser → modelo: headings 1-6, listas anidadas, blockquote, code block con/sin lenguaje, tabla, estilos inline, link, input malformado.
- `FolderScanner`: filtra .md/.markdown case-insensitive, ignora otros formatos, poda carpetas vacías, recursivo, carpeta vacía.
- `TOCBuilder`: niveles, títulos duplicados con ids únicos, documento sin headings.
- `LinkClassifier`: https, http, mailto, ancla, esquema desconocido, URL inválida.
- Default-app checker con `WorkspaceServicing` falso: ya es predeterminada, no lo es, "no volver a preguntar", error del sistema.
- ViewModels: estados loading/loaded/error.

## Open source

- `LICENSE` MIT, `README.md` (descripción, features, screenshot placeholder, build con Xcode 27, decisión de links), `.gitignore` para Xcode.
