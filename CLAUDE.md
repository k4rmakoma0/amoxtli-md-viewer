# Amoxtli: Markdown Editor

Editor de Markdown para macOS 27, pensado también para quien no es programador. Gratuito y 100% open source (MIT). Xcode 27, Swift 6.

## Identidad

- Bundle ID: `dev.alananaya.amoxtli`
- Nombre en README/App Store: "Amoxtli: Markdown Editor" (en español, "Amoxtli: Editor de Markdown"). Las cadenas de la app dicen "app predeterminada para Markdown", no "visor".
- `PRODUCT_NAME` y `CFBundleDisplayName`: `Amoxtli` (sin dos puntos: el nombre del .app es un nombre de archivo)
- Target/scheme: `Amoxtli`

## Reglas del proyecto

- 100% nativo: solo Foundation, SwiftUI, AppKit, UniformTypeIdentifiers. Cero dependencias de terceros, sin WKWebView.
- SwiftUI es la base. AppKit solo donde SwiftUI no alcance (ver Links), con un comentario que lo justifique.
- MVVM, async/await, sin singletons.
- Estructura: `App/`, `Domain/`, `Presentation/`, `Services/`, `Resources/`.
- Tipado fuerte, funciones pequeñas, sin duplicación, sin force unwrap, código testeable.
- No inventes APIs. Si no estás seguro de que una API exista en Xcode 27 / macOS 27, dilo y verifica contra la documentación antes de usarla.
- Errores explícitos: UTF-8 inválido, archivo ilegible, bookmark obsoleto, carpeta sin markdowns, guardado fallido (estado vacío o alert con mensaje). Un archivo vacío NO es error: se abre listo para escribir, y la vista con formato muestra "Documento vacío" con botón Escribir.
- Un archivo que no se pudo decodificar se abre en solo lectura y nunca se sobrescribe.

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
5. Edición en Fuente (archivo y carpeta) + herramientas de formato
6. Selector de fuente y tamaño
7. Formato WYSIWYG editable
8. Vista dividida sincronizada, ambos lados editables
9. Pulido: cambios externos al archivo, accesibilidad del editor, README y nombre

## Parsing y render

- `AttributedString(markdown:options:)` con `interpretedSyntax: .full` y `failurePolicy: .returnPartiallyParsedIfPossible`.
- `<u>`/`</u>` (y `<ins>`) llegan como runs de HTML inline: se convierten en el estilo subrayado. Cualquier otro HTML se queda como texto.
- Agrupar runs por `PresentationIntent` hacia un modelo propio en `Domain/`: heading(level), paragraph, orderedList, unorderedList, listItem, blockQuote, codeBlock(languageHint), table, thematicBreak. Estilos inline desde `InlinePresentationIntent`, links desde `.link`.
- El modelo alimenta el índice, las estadísticas y el editor con formato (ver Edición). No hay un render de solo lectura aparte: el modo Formato es el editor.
- Code blocks: monoespaciada del sistema. Fondo del código (en línea y bloques), encabezado y líneas de tabla en `SurfaceColors`, con valor claro, oscuro y con Aumentar contraste (los rellenos del sistema casi no se ven en oscuro). La cuadrícula de las tablas la dibuja `RichLayoutManager` completa en cada redibujado, no TextKit (que la perdía al redibujar parte de la tabla). Resaltado por lenguaje con `CodeHighlighter` (`Domain/`): un lexer escrito a mano por familia (comentarios, cadenas, números, palabras clave, tipos, propiedades, etiquetas/atributos), sin dependencias. `CodeLanguage` lee el info string del fence (con alias: js, ts, py, sh, bash, zsh, xml…): Swift, Python, JavaScript, TypeScript, JSON, HTML/XML, CSS, SQL y Shell; cualquier otro lenguaje queda sin color. Se colorea el bloque entero (comentarios y cadenas de varias líneas). Colores en `CodeColors`, con valor claro y oscuro (cercanos al tema de Xcode), iguales en Fuente y en Formato. Imágenes http(s) cargadas en segundo plano.
- No asumas soporte GFM (tablas, strikethrough, task lists): verifícalo con tests y reporta qué funciona.

## Modos de apertura

1. **Un archivo** (.md/.markdown desde Finder, Open With o ⌘O): `DocumentGroup(newDocument:)` con `MarkdownDocument: ReferenceFileDocument` (⌘N crea uno). La ventana muestra SOLO contenido e índice. NO hay lista de archivos.
2. **Una carpeta** (File > Open Folder…, ⇧⌘O, `NSOpenPanel` con `canChooseDirectories`): ventana propia (`WindowGroup(for:)` con security-scoped bookmark `Data` como valor). `NavigationSplitView`: sidebar con selector segmentado Índice / Archivos, detalle con el contenido.
   - Escaneo recursivo con `FileManager`, SOLO .md y .markdown (extensión case-insensitive), agrupado por subcarpeta, omitiendo carpetas sin markdowns. Escaneo fuera del main actor. Orden alfabético localizado.
   - Restauración de ventanas con el bookmark.

3. **Sin nada que abrir** (inicio o clic en el Dock sin ventanas): ventana de bienvenida (`Window`, `.defaultLaunchBehavior(.presented)`) con Nuevo documento, Abrir archivo… y Abrir carpeta…. Reemplaza el panel de inicio del sistema (`applicationShouldOpenUntitledFile` → `false`), que solo elige archivos. Se cierra al abrir algo.
- Botón Abrir en el toolbar de ambas ventanas: clic abre archivo, su menú también ofrece carpeta.

## Edición

- Modos por ventana (`@SceneStorage("editorMode")`): **Fuente** (Markdown con resaltado), **Formato** (WYSIWYG editable) y **Dividido** (`HSplitView` con los dos editores, ambos editables). Selector segmentado al inicio del toolbar (junto a Abrir, para que no se vaya al menú »); Visualización > Mostrar fuente / con formato / dividido (⌃⌘1–3).
- El texto Markdown es siempre la fuente de verdad. El editor de Fuente es una subclase de `NSTextView` (TextKit 2, `isRichText = false`, sin sustituciones automáticas que rompan la sintaxis) en un `NSViewRepresentable`.
- Undo: el text view usa el undo manager del documento (`undoManager(for:)`), así escribir marca el documento como editado.
- Resaltado incremental: `MarkdownSyntaxScanner` (`Domain/`) escanea solo las líneas editadas desde `textStorage(_:willProcessEditing:)`; si la edición abre o cierra un bloque de código, re-escanea lo que sigue.
- Sincronización en Dividido: los dos editores escriben al mismo texto Markdown. Fuente aplica solo la diferencia mínima (`TextDifference`), conservando cursor, scroll y resaltado. Formato se reconstruye 200 ms después de la última edición ajena, conservando scroll y cursor. Antes de aceptar un cambio o al recibir el foco, cada editor compara contra el texto actual del binding y se pone al día, así nunca escribe sobre una versión vieja.
- Scroll sincronizado en Dividido (`SplitScrollSync`): manda el lado que se desplaza con la rueda, el trackpad o la barra, y si no, el que tiene el foco; el otro lo sigue. Se empareja bloque por bloque (`MarkdownParser.topLevelBlockLines` en Fuente, `RichTopLevelBlocks` en Formato) e interpola entre bloques (`SplitScrollMap`); si los dos lados no cuentan los mismos bloques, solo alinea inicio y fin. Tras editar, el otro lado se pone al día 250 ms después.
- Documentos grandes: Formato y Dividido admiten hasta 1 MB (`FormattedEditingLimit`, bytes UTF-8). Más grande abre en Fuente; elegir Formato o Dividido muestra "Documento demasiado grande" con botón Mostrar fuente, y el editor con formato nunca se construye. Al estilizar texto largo (`RichTextConverter`, `SourceHighlighter`), los atributos se aplican de principio a fin por tramos: cambiarlos lejos del final recorre todos los tramos siguientes y lo vuelve cuadrático.
- Cada documento tiene editores propios (`.id(documentID)`); al salir de pantalla, cada editor quita sus pasos de undo.
- Índice y estadísticas salen del texto 250 ms después de la última edición (`DocumentViewModel.update`), un parseo a la vez: lo que llega mientras corre espera y solo se parsea lo más reciente. Clic en el índice: todos los editores en pantalla van al título (`SourceHeadingLocator` en Fuente, n-ésimo título en Formato).
- Formato WYSIWYG (`Presentation/Rich/`): `RichTextView`, subclase de `NSTextView` con TextKit 1 (necesario para `NSTextTable`). Nunca muestra sintaxis.
  - Modelo plano en `Domain/RichDocument.swift`: `RichParagraph` (bloque + contenedores quote/listItem con ids + runs). `RichDocumentBuilder` lo arma desde `MarkdownModel`; `MarkdownSerializer` lo escribe como Markdown canónico (`-`, `**`, `*`, fences, escapes mínimos). Garantía: `parse(serialize(x)) == parse(x)`, cubierta por tests de ida y vuelta.
  - En el texto, cada párrafo lleva `.richParagraph` (`RichParagraphKind`) y cada run `.inlineStyle`; las fuentes y el estilo de párrafo se derivan de ahí (`RichStyler`). Tras cada edición, cada párrafo toma el tipo de su primer carácter y se re-estiliza con sus vecinos (`RichTextNormalizer`, en `didChangeText`).
  - `RichLayoutManager` dibuja viñetas/números (se renumeran solos), la barra de las citas y el fondo del código (esquinas redondeadas en los extremos del bloque). Línea divisoria e imágenes son adjuntos; las imágenes remotas cargan en segundo plano.
  - El fence no se ve en Formato: cada bloque de código empieza con una franja con un chip arriba a la derecha (nombre del lenguaje, o "Elegir lenguaje" sin uno, con ⌄). Clic en el chip (cursor de mano) abre el menú de lenguajes; también clic derecho > Lenguaje ▸ (Ninguno + los conocidos; uno desconocido del archivo aparece marcado). Se escribe en el fence al serializar. A la izquierda del chip, un botón Copiar (`RichTextView+CodeCopy`) copia el código del bloque como texto plano, sin el fence, y muestra una palomita un momento; también clic derecho > Copiar código. TextKit 1 no aplica espaciado antes del primer párrafo y recorta lo que se dibuja arriba de él, así que la franja de un bloque que empieza el texto la dibuja la vista en el margen superior (que crece con el tamaño de letra).
  - Solo se serializa al editar en Formato: abrir o leer no reescribe el archivo. La primera edición deja el archivo en forma canónica.
  - Teclas como en Pages: Return en lista crea ítem, en ítem vacío sale de la lista, al final de un título sigue texto normal; Borrar al inicio quita viñeta/cita/título antes de unir; Tab/⇧Tab anidan y desanidan ítems y en tablas cambian de celda. En un bloque de código, Return siempre agrega una línea (también en blanco); ↓ en su última línea al final del documento sale a texto normal. Pegar es siempre texto plano.
  - Tablas editables por celda; agregar o quitar filas y columnas se hace en Fuente.
- Herramientas de formato (`FormatTool` → `FormatCommand`; en Fuente, `MarkdownFormatter` puro en `Domain/`; en Formato, `RichTextView+Formatting`; `EditorController` las manda al editor activo vía `FormattingTarget`): Texto/Título 1–6 (⌘7, ⌘1–⌘6), negrita ⌘B, cursiva ⌘I, subrayado ⌘U (`<u>…</u>`), tachado ⇧⌘X, código ⌘E, cita ⌘', viñetas ⇧⌘8, numerada ⇧⌘7, enlace ⌘K (hoja con texto y dirección, `LinkInput` normaliza), bloque de código ⌥⌘C, tabla, línea divisoria. Funcionan como interruptor y cada una es un paso de undo.
- Viven en tres lugares: toolbar personalizable (`.toolbar(id:)`), menú Formato y submenú Formato del clic derecho (`EditingContextMenu`: Cortar, Copiar, Pegar, Formato ▸, Seleccionar todo). Deshabilitadas si no hay editor en pantalla.
- Tipografía global (`@AppStorage`, `TypographyPreferences`): tipo de letra curado (`ReadingFont`: Sistema, Serif/New York, Monoespaciada, Redondeada, vía `NSFontDescriptor.SystemDesign`) y tamaño por pasos (`TextSize`, 10–32 pt, estándar 13, valores guardados se ajustan al paso más cercano). Se aplica a Fuente y a Formato por el environment `\.typography`; títulos escalan con el cuerpo y el código siempre es monoespaciado. Menú Aa en el toolbar y en Visualización: Aumentar ⌘+, Reducir ⌘−, Tamaño normal ⌘0.
- Modo carpeta: `FolderFileEditor` guarda 1 s después de la última edición, al cambiar de archivo, al cerrar la ventana y al salir. Escritura atómica. Si falla, alert explicando permisos.
- Cambios externos (`ExternalChange` en `Domain/`, fechas de modificación vía `FileDating`): al activarse la app, los documentos sin cambios sin guardar se recargan (`ExternalDocumentChanges` llama a `NSDocument.revert`; `DocumentGroup` no lo hace solo). En carpeta, `FolderFileEditor` recarga si no hay nada sin guardar y si hay, alerta para elegir versión; tampoco guarda encima de un archivo que cambió. La fecha se lee como la lee `NSDocument` (resource value sin caché) para no disparar recargas falsas.
- Accesibilidad del editor con formato: cada primer párrafo de ítem lleva `.accessibilityListItemPrefix`, `Index` y `Level` (`RichListMarker`, compartido con el dibujo), así VoiceOver anuncia viñetas y números. No existe una llave equivalente para títulos.

## Índice (TOC)

- Generado desde los headings del modelo, indentado por nivel, con ids únicos aunque se repitan títulos.
- Sidebar izquierdo de `NavigationSplitView` en ambos modos (`ReaderSplitView`). En modo archivo solo muestra el índice; en modo carpeta, un `Picker` segmentado alterna entre índice y lista de archivos. Ocultable con el botón de sidebar del sistema y ⌃⌘S; visibilidad y pestaña persistidas con `@SceneStorage`. Cada segmento tiene tooltip (`.help`), y Visualización > Mostrar índice (⌥⌘1) / Mostrar archivos (⌥⌘2) muestran el sidebar en esa pestaña.

## Estadísticas de lectura

- `ReadingStats` en `Domain/`: palabras de headings, párrafos, listas, citas y tablas (sin código ni imágenes), con límites de palabra del sistema. Tiempo a 200 palabras/min; menos de 200 palabras → "menos de 1 min".
- Se muestran en una franja propia debajo del editor (no `safeAreaBar`: los editores son scroll views de AppKit, que no se detienen sobre la barra ni difuminan el texto que pasa debajo, y `HSplitView` la ignora), alineado a la derecha, texto secundario.
- Click en una entrada del índice: los editores van al heading sin animación.

## Links

- Clasificador (enum en `Domain/`): http/https y mailto → sistema; ancla `#x` → scroll al heading; cualquier otro esquema → ignorar y avisar con un indicador discreto, nunca abrir en silencio.
- Hover sobre un link: cursor `pointingHand` y pill en la esquina inferior izquierda con la URL completa (truncada al medio), estilo status bar de Safari. Desaparece al salir.
- Menú contextual sobre un link:
  - Abrir en navegador predeterminado (resolver con `NSWorkspace.shared.urlForApplication(toOpen:)` y mostrar su nombre)
  - Abrir con ▸ submenú con las apps de `NSWorkspace.shared.urlsForApplications(toOpen:)`, con icono (`NSWorkspace.shared.icon(forFile:)`) y nombre; la predeterminada marcada; abrir con `NSWorkspace.shared.open(_:withApplicationAt:configuration:)`
  - Copiar enlace
- Menú contextual sobre texto: `EditingContextMenu` (Cortar, Copiar, Pegar, Formato ▸, Seleccionar todo).
- Implementación en `RichTextView` (AppKit, porque SwiftUI `Text` no expone hover ni menú por link): hover con `NSTrackingArea` + `mouseMoved` y el layout manager (`NSTextView+Links`), clic con `clicked(onLink:)`, menú con override de `menu(for:)`. Anclas `#x` llegan como `scrollRequest` y el editor va al título.

## App predeterminada para Markdown

- Info.plist: `UTImportedTypeDeclarations` para `net.daringfireball.markdown` (extensiones md, markdown; conforma a `public.plain-text`) y `CFBundleDocumentTypes` con rol Editor.
- Al iniciar: si la app NO es la predeterminada (comparar `NSWorkspace.shared.urlForApplication(toOpen:)` con `Bundle.main.bundleURL`), mostrar alert propio "Usar Amoxtli para abrir archivos Markdown" con [Establecer como predeterminada] [Ahora no] y checkbox "No volver a preguntar" (UserDefaults).
- Al aceptar: `NSWorkspace.shared.setDefaultApplication(at:toOpen:)` (async throws) para el UTType de Markdown. El sistema muestra su propia confirmación; maneja error y cancelación sin crashear.
- Menú de la app: "Establecer como app predeterminada para Markdown…" siempre disponible.
- Encapsula `NSWorkspace` detrás de un protocolo mínimo (`WorkspaceServicing`) solo para testear.

## Diseño nativo (macOS 27 / Liquid Glass)

- Componentes del sistema (toolbar, `NavigationSplitView`, menús, alerts) para heredar Liquid Glass automáticamente. Prohibido simular glass con Material/blur propios en el chrome.
- El contenido NO es glass. El pill de URL y cualquier control flotante propio usan `glassEffect` dentro de `GlassEffectContainer`, con fallback sólido cuando `accessibilityReduceTransparency` esté activo.
- Toolbar estándar, `ToolbarSpacer` para agrupar. Sin title bar custom.
- Fuentes del sistema, colores semánticos, SF Symbols, accent color del usuario, light/dark automático.
- Ancho de lectura máx. ~800 pt centrado, padding generoso.
- Accesibilidad: VoiceOver (labels en TOC, links y lista de archivos), Reduce Transparency, Reduce Motion, Increase Contrast. Todo operable por teclado.

## Sandbox / seguridad

- App Sandbox con `com.apple.security.files.user-selected.read-write` (`ENABLE_USER_SELECTED_FILES = readwrite`) y `com.apple.security.files.bookmarks.app-scope`. `com.apple.security.network.client` solo por imágenes remotas.
- Sin telemetría. Validar todo input.

## Tests (XCTest)

- `MarkdownDocument` / `MarkdownDecoder`: UTF-8 válido, vacío (válido), bytes inválidos (no se escribe), archivo grande.
- `TextSize` / `Typography`: pasos y límites, ajuste de valores guardados, títulos escalan, código monoespaciado.
- `MarkdownFormatter`: cada herramienta aplica y quita su sintaxis, selección resultante, offsets UTF-16.
- `ExternalChange` / `FolderFileEditor`: recarga sin cambios locales, conflicto con cambios locales, no guarda encima, conservar la mía, usar la del disco, archivo borrado.
- `TextDifference`: inserción, borrado, reemplazo, caracteres de dos unidades UTF-16, ajuste de la selección; Fuente conserva el cursor al recibir texto de Formato.
- `MarkdownSerializer`: ida y vuelta para estilos, listas anidadas, citas, código, tablas, links, saltos forzados y texto que parece sintaxis; salida canónica estable.
- `RichTextView`: conversión sin pérdida, Return/Borrar/Tab en listas, títulos y tablas, cada herramienta de formato.
- `MarkdownSyntaxScanner`: spans por tipo, nada se resalta dentro de código, estado de fence entre líneas.
- `CodeHighlighter` / `CodeLanguage`: tokens por lenguaje, comentarios y cadenas de varias líneas, offsets UTF-16, alias del fence; ambos editores colorean y recolorean al editar; elegir el lenguaje en Formato escribe el fence.
- `FolderFileEditor`: carga sin marcar cambios, autoguardado, guarda al cambiar de archivo, error de escritura, archivo ilegible nunca se escribe.
- Parser → modelo: headings 1-6, listas anidadas, blockquote, code block con/sin lenguaje, tabla, estilos inline, link, input malformado.
- `FolderScanner`: filtra .md/.markdown case-insensitive, ignora otros formatos, poda carpetas vacías, recursivo, carpeta vacía.
- `TOCBuilder`: niveles, títulos duplicados con ids únicos, documento sin headings.
- `LinkClassifier`: https, http, mailto, ancla, esquema desconocido, URL inválida.
- Default-app checker con `WorkspaceServicing` falso: ya es predeterminada, no lo es, "no volver a preguntar", error del sistema.
- ViewModels: estados loading/loaded/error.

## Open source

- `LICENSE` MIT, `README.md` (descripción, features, screenshot placeholder, build con Xcode 27, decisión de links), `.gitignore` para Xcode.
