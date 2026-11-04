# App Review notes

Reply to App Review (Guideline 2.1, Information Needed) and text for **App Review Information > Notes** in App Store Connect. Paste everything inside the block. It stays under the 4,000-character limit of the Notes field.

```text
Hello, and thank you for reviewing Amoxtli.

1. SCREEN RECORDING
Attached. It was recorded on a Mac (Apple silicon) running the latest macOS, starting from launching the app. Amoxtli has no account registration or login, no user-generated content shared with others, and no paid content, so none of those flows exist.

2. PURPOSE AND AUDIENCE
Amoxtli is a free, open-source (MIT), read-only viewer for Markdown files (.md, .markdown) on the Mac. Markdown is the plain-text format used for README files, documentation, and notes. By default, macOS opens it in TextEdit as raw text with all the syntax visible. Amoxtli shows it with headings, lists, tables, code blocks, and images, plus a table of contents and reading time.
Audience: developers, technical writers, students, and anyone who receives or keeps notes and documentation in Markdown.
It also protects the reader from misleading links: hovering a link shows its full URL, unfamiliar sites show a warning before opening, and a link whose text names a different site always shows a warning.

3. HOW TO USE IT
No login, account, or setup is required. Sample files are available here (download the repository as ZIP, or the "sample" folder):
https://github.com/k4rmakoma0/amoxtli-md-viewer/tree/main/docs/app-review/sample
Any .md file on the Mac also works.
- Launch the app: a Welcome window offers Open File… and Open Folder…. On first launch, the app may ask to become the default Markdown viewer; choose Set as Default or Not Now.
- Open a file: Open File… (⌘O), or double-click a .md file in Finder. Open "Welcome.md".
- Table of contents: shown in the sidebar (⌃⌘S to show or hide). Click an entry to scroll to that section. Word count and reading time appear at the bottom right.
- Links: hover a link to see its URL in the bottom-left corner. Right-click it for Open in [browser], Open With, and Copy Link. Click the "Example" link to see the warning for an unfamiliar site.
- Open a folder: File > Open Folder… (⇧⌘O) and choose the "sample" folder. The sidebar lists every Markdown file, including subfolders, grouped by folder. Use the Contents / Files switch (⌥⌘1 / ⌥⌘2) at the top of the sidebar.
- App menu > Set as Default Markdown Viewer… is always available.

4. EXTERNAL SERVICES
None. Amoxtli uses no third-party SDKs, servers, analytics, authentication, payments, or AI services. All parsing and rendering happen on the device with Apple frameworks (Foundation, SwiftUI, AppKit). The only network access (com.apple.security.network.client) is to load remote images referenced inside the documents the user opens, from the servers chosen by each document's author. Links open in the user's browser only when the user chooses to open them.

5. REGIONAL DIFFERENCES
None. The app works the same in all regions. It is localized into 11 languages (English, Spanish, French, German, Italian, Brazilian Portuguese, Russian, Japanese, Korean, Simplified Chinese, and Traditional Chinese); only the interface language changes.

6. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable. Amoxtli does not operate in a regulated industry and includes no protected third-party content. It only displays files the user opens. All code is original and published under the MIT license:
https://github.com/k4rmakoma0/amoxtli-md-viewer

Privacy policy: https://amoxtli.alananaya.dev/privacy/
Support: https://github.com/k4rmakoma0/amoxtli-md-viewer/issues

Thank you,
Alan Anaya
```

## Guion de la grabación (2 a 3 minutos)

Graba en tu Mac con ⇧⌘5 > Grabar toda la pantalla. Usa la app del build que subiste (de TestFlight o la misma versión), no la de Xcode. Antes de grabar, deja la carpeta `sample` en el Escritorio y, si quieres que salga el alert de app predeterminada, quita Amoxtli como predeterminada o borra sus preferencias.

1. Escritorio limpio, Amoxtli cerrada. Ábrela desde el Dock o Launchpad: se ve la ventana de bienvenida (y el alert de app predeterminada, si aparece).
2. Open File… > `Welcome.md`. Haz scroll lento por todo el documento: estilos, listas, cita, código, tabla, imagen.
3. Clic en dos o tres entradas del índice. Señala el conteo de palabras abajo a la derecha. Oculta y muestra el sidebar con ⌃⌘S.
4. Pasa el cursor sobre un link (se ve la URL abajo a la izquierda). Clic derecho para mostrar el menú. Clic en "Example": sale el aviso, elige Cancelar. Clic en "Back to the top".
5. File > Open Folder… > `sample`. Cambia a Archivos, abre `Keyboard Shortcuts.md` y `Meeting Notes.md`, vuelve a Índice.
6. Doble clic en un .md desde Finder para mostrar que abre en Amoxtli.
7. Menú Amoxtli > Set as Default Markdown Viewer…. Cierra la app.

Exporta en 1080p si el archivo pesa mucho. App Store Connect acepta .mov y .mp4 adjuntos en la respuesta.
