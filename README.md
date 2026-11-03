# Amoxtli: Markdown Editor

Editor de Markdown para macOS 27, pensado también para quien no es programador. Gratuito y 100% open source (MIT). Nativo: solo frameworks de Apple, sin dependencias de terceros y sin WKWebView.

![Captura de pantalla](docs/screenshot.png) <!-- placeholder -->

## Funciones

- **Tres formas de editar**, con un selector al inicio de la barra o con ⌃⌘1, ⌃⌘2 y ⌃⌘3:
  - **Formato:** se escribe como en un procesador de texto y nunca se ve la sintaxis de Markdown. Amoxtli guarda el Markdown.
  - **Fuente:** el Markdown con resaltado.
  - **Dividido:** los dos lado a lado, ambos editables y sincronizados.
- **Herramientas de formato** en la barra, en el menú Formato y en el clic derecho: títulos 1 a 6 (⌘1 a ⌘6, ⌘7 para texto normal), negrita ⌘B, cursiva ⌘I, subrayado ⌘U, tachado ⇧⌘X, código ⌘E, cita ⌘', listas con viñetas ⇧⌘8 y numeradas ⇧⌘7, enlace ⌘K, bloque de código ⌥⌘C, tabla y línea divisoria. Todas funcionan como interruptor. La barra se puede personalizar.
- **En Formato, las teclas funcionan como en Pages:** Return en una lista crea un ítem y en un ítem vacío sale de la lista. Borrar al inicio de un párrafo quita la viñeta, la cita o el título antes de unirlo con el de arriba. Tab y ⇧Tab anidan y desanidan ítems, y en una tabla cambian de celda. Pegar siempre pega texto plano.
- **Tipo de letra y tamaño:** Sistema, Serif, Monoespaciada o Redondeada, y tamaño con ⌘+, ⌘− y ⌘0, desde el menú Aa de la barra o el menú Visualización. Se aplica a todos los modos y el código sigue en monoespaciada.
- Abre archivos `.md` y `.markdown` desde Finder, Open With o ⌘O, y crea documentos nuevos con ⌘N.
- Si se abre sin nada, muestra una ventana de bienvenida para crear un documento, abrir un archivo o abrir una carpeta. El botón Abrir de la barra también abre archivos y carpetas en cualquier ventana.
- Abre carpetas con File > Open Folder… (⇧⌘O): lista sus archivos Markdown, también los de subcarpetas, agrupados por carpeta, y permite editarlos. Los cambios se guardan solos. La ventana se restaura al volver a abrir la app.
- **Cambios hechos en otra app:** al volver a Amoxtli, si el archivo cambió y aquí no hay nada sin guardar, se muestra la versión nueva. Si hay cambios sin guardar, una carpeta pregunta qué versión conservar; un documento suelto deja que macOS avise antes de guardar encima.
- Barra lateral con el índice del documento. En una carpeta, un selector alterna entre el índice y la lista de archivos. Se oculta con el botón de la barra o con ⌃⌘S, y ⌥⌘1 y ⌥⌘2 la muestran en el índice o en los archivos. Al elegir una entrada del índice, los editores van a su encabezado.
- Conteo de palabras y tiempo estimado de lectura (200 palabras por minuto) en la esquina inferior. No cuenta los bloques de código.
- Se ofrece como app predeterminada para Markdown al iniciar, con la opción de no volver a preguntar. También se puede establecer desde el menú de la app.
- Explica los errores en la ventana: UTF-8 inválido, archivo ilegible, carpeta sin Markdown, carpeta que ya no se encuentra o archivo que no se pudo guardar. Un archivo que no se pudo leer se muestra sin editar y nunca se sobrescribe.
- Abre links web y de correo con el sistema, y los links `#ancla` llevan al encabezado. Cualquier otro esquema se ignora y se avisa.
- Al pasar el mouse sobre un link muestra su URL completa, como la barra de estado de Safari.
- Menú contextual en links: abrir en la app predeterminada, "Abrir con" y copiar el enlace.
- Avisa antes de abrir un link a un sitio que no conoce. Ver [Enlaces conocidos](#enlaces-conocidos).
- VoiceOver anuncia las viñetas y los números de las listas en el modo Formato.
- Disponible en inglés, español, francés, alemán, italiano, portugués de Brasil, ruso, japonés, coreano y chino simplificado y tradicional.

## Soporte de Markdown

El parser es `AttributedString(markdown:)` de Foundation. Los tests de `AmoxtliTests/MarkdownParserTests.swift` documentan este comportamiento:

| Sintaxis | Estado |
|---|---|
| Tablas GFM, con alineación | Funciona |
| Tachado (`~~x~~`) | Funciona |
| Subrayado (`<u>x</u>` o `<ins>x</ins>`) | Funciona: Markdown no tiene subrayado y esta es la forma que usan la mayoría de editores |
| Autolinks (`https://…`) | Funciona |
| Task lists (`- [ ] x`) | No se interpreta: aparece como texto literal |
| Notas al pie (`[^1]`) | No se interpreta: aparece como texto literal |
| Salto de línea duro (dos espacios o `\` al final) | Funciona |
| Otro HTML | No se interpreta: aparece como texto literal |
| Imágenes con ruta relativa | No se cargan: se muestra un ícono |

## Cómo guarda el modo Formato

El texto Markdown es siempre la fuente de verdad. Abrir o leer un archivo nunca lo reescribe, ni siquiera en el modo Formato. La primera edición que hagas en Formato escribe el documento completo en forma canónica:

| Antes | Después |
|---|---|
| `* item` o `+ item` | `- item` |
| `__fuerte__`, `_suave_` | `**fuerte**`, `*suave*` |
| Títulos subrayados con `===` o `---` | `# Título`, `## Título` |
| Listas numeradas con saltos (`1.`, `1.`, `1.`) | Numeración seguida desde el primer número |
| Código con sangría de cuatro espacios | Código entre ` ``` ` |

Lo que el documento dice no cambia: `MarkdownSerializerTests` comprueba que volver a leer lo escrito da exactamente el mismo documento. Los caracteres que Markdown leería como sintaxis, como un `#` al inicio de un párrafo o un `*` pegado a una palabra, se escriben escapados. Editar en Fuente no cambia nada más que lo que escribes.

## Editor con formato: por qué `NSTextView` y TextKit 1

SwiftUI no tiene una vista de texto enriquecido editable, y `WKWebView` está descartado. El modo Formato es una subclase de `NSTextView` (`RichTextView`) con TextKit 1, porque las tablas editables usan `NSTextTable` y solo TextKit 1 las dibuja.

- **Modelo:** el documento se aplana en párrafos (`RichParagraph`). Cada uno sabe qué es (párrafo, título, línea de código, celda, imagen o línea divisoria) y dentro de qué está (citas e ítems de lista, con ids). Una vista de texto edita párrafos, no árboles, y esta forma sobrevive a la escritura y alcanza para escribir el Markdown de vuelta.
- **Atributos:** cada párrafo guarda su tipo y cada fragmento su estilo en atributos propios. Las fuentes, las sangrías y los espacios se derivan de ahí, así que re-estilizar un párrafo nunca depende de cómo se veía antes.
- **Dibujo:** un `NSLayoutManager` propio dibuja las viñetas y los números (que se renumeran solos), la barra de las citas y el fondo del código. Por eso la sintaxis nunca está en el texto.
- **Links:** el hover usa `NSTrackingArea`, `mouseMoved` y `NSLayoutManager.characterIndex(for:in:fractionOfDistanceBetweenInsertionPoints:)` leyendo el atributo `.link`. No usa `characterIndexForInsertion(at:)` porque en una ventana visible devuelve el final del texto. El menú es un override de `menu(for:)`. SwiftUI `Text` no sirve aquí: `onHover`, `onContinuousHover` y `contextMenu` actúan sobre la vista completa, no sobre un link.
- **Vista dividida:** los dos editores escriben al mismo texto. Fuente aplica solo la diferencia mínima, así que conserva el cursor y el scroll. Formato se reconstruye tras una pausa breve. Antes de aceptar un cambio, cada uno se pone al día con el texto actual, así nunca escribe sobre una versión vieja.

## Enlaces conocidos

Un documento puede decir una cosa y enlazar a otra, así que Amoxtli no abre cualquier sitio sin avisar. Cada link web pasa por esta revisión, ya sea con un clic o desde el menú contextual:

- **Se abren directo:** `apple.com`, `github.com`, `mozilla.org`, `swift.org` y `wikipedia.org`, con sus subdominios, y los sitios en los que elegiste confiar. También los links `mailto:`, porque solo crean un borrador.
- **Muestran una alerta:** todos los demás sitios. La alerta enseña el dominio y la URL completa, y permite "Confiar siempre" en ese sitio.
- **Muestran otra alerta, siempre:** los links cuyo texto nombra un sitio distinto de su destino, como `[apple.com](https://otro-sitio.example)`, aunque el destino sea conocido o de confianza. Esta alerta no ofrece confiar en el sitio.
- **Nunca se abren:** los demás esquemas, como `ftp:` o `file:`.

La comparación es por dominio completo: `notgithub.com` y `github.com.example.org` no cuentan como GitHub. Para borrar los sitios de confianza, usa "Olvidar sitios de confianza" en el menú de la app.

Un texto cuenta como dirección si empieza con `http://`, `https://` o `www.`, si es un correo, o si termina en un dominio común en minúsculas, como `.com` o `.org`. Así, `README.md` y `ASP.NET` no disparan la alerta. Los subdominios del mismo sitio tampoco: `apple.com` puede llevar a `support.apple.com`.

## Carpetas

El escaneo omite archivos y carpetas ocultos, el contenido de paquetes como las apps y los enlaces simbólicos. Una subcarpeta sin permiso de lectura se omite y no impide abrir el resto.

El archivo elegido se guarda un segundo después de la última edición, al cambiar de archivo, al cerrar la ventana y al salir. Nunca se escribe encima de una versión que cambió en otra app: Amoxtli pregunta primero. Las carpetas abiertas con Amoxtli 1.2 o anterior tienen permiso solo de lectura; si guardar falla, hay que volver a abrirlas.

La lista refleja la carpeta en el momento de abrirla: para ver archivos nuevos hay que cerrar la ventana y abrirla otra vez. Los links relativos entre archivos, como `otra-nota.md`, no navegan: se ignoran y se avisa, igual que cualquier otro esquema.

## Compilar

Requiere Xcode 27 y macOS 27.

```bash
xcodebuild -scheme Amoxtli -destination 'platform=macOS' build
```

```bash
xcodebuild -scheme Amoxtli -destination 'platform=macOS' test
```

## Publicar una versión

`packaging/release.sh` parte de un commit limpio, corre los tests y usa `MARKETING_VERSION` como versión. Como número de build usa la cantidad de commits, así que los dos canales comparten el mismo.

La firma usa los certificados que Xcode administra en la nube, así que basta con tener la cuenta del equipo en Xcode > Settings > Accounts. Lo único que hay que preparar, una sola vez, son las credenciales de notarización en el llavero:

```bash
xcrun notarytool store-credentials amoxtli-notary --apple-id <tu-apple-id> --team-id EWLRV4247C
```

Para Homebrew, este comando genera en `build/release` el zip notarizado y el cask. También imprime los pasos para publicarlos:

```bash
packaging/release.sh developer-id
```

Para App Store, crea primero la app en App Store Connect con el mismo bundle ID. Este comando sube el build:

```bash
packaging/release.sh app-store
```

## Privacidad

Amoxtli no recopila datos. Ver la [política de privacidad](PRIVACY.md).

## Licencia

[MIT](LICENSE)
