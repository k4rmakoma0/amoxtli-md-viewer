import AppKit

// Composes the App Store screenshots: each captured window (raw-<scene>.png) on a gradient,
// under its caption in every language. Run by make-screenshots.sh.
//
// Usage: swift compose.swift <raw dir> <output dir>
let raw = URL(filePath: CommandLine.arguments[1])
let out = URL(filePath: CommandLine.arguments[2])

let scenes = ["1-write", "2-split", "3-folder", "4-dark"]
let captions: [String: [String]] = [
    "en": ["Write Markdown like a document", "Markdown and formatted, side by side", "Edit a whole folder of notes", "Your typeface, light or dark"],
    "es": ["Escribe Markdown como un documento", "Markdown y con formato, lado a lado", "Edita una carpeta completa de notas", "Tu tipo de letra, en claro u oscuro"],
    "fr": ["Écrivez du Markdown comme un document", "Markdown et mis en forme, côte à côte", "Modifiez tout un dossier de notes", "Votre police, en clair ou en sombre"],
    "de": ["Markdown schreiben wie ein Dokument", "Markdown und formatiert nebeneinander", "Einen ganzen Ordner voller Notizen bearbeiten", "Deine Schrift, hell oder dunkel"],
    "it": ["Scrivi Markdown come un documento", "Markdown e formattato, affiancati", "Modifica un’intera cartella di note", "Il tuo font, chiaro o scuro"],
    "pt-BR": ["Escreva Markdown como um documento", "Markdown e formatado, lado a lado", "Edite uma pasta inteira de notas", "Sua fonte, no claro ou no escuro"],
    "ru": ["Пишите Markdown как обычный документ", "Markdown и форматирование рядом", "Редактируйте целую папку заметок", "Ваш шрифт в светлой или темной теме"],
    "ja": ["書類のようにMarkdownを書く", "Markdownと書式付きを並べて", "フォルダ内のメモをまとめて編集", "好きな書体で、ライトでもダークでも"],
    "ko": ["문서처럼 Markdown 쓰기", "Markdown과 서식을 나란히", "폴더 속 메모를 한곳에서 편집", "원하는 서체로, 라이트 또는 다크"],
    "zh-Hans": ["像写文稿一样写 Markdown", "Markdown 与格式并排显示", "编辑整个文件夹的笔记", "你的字体，浅色或深色"],
    "zh-Hant": ["像寫文件一樣寫 Markdown", "Markdown 與格式並排顯示", "編輯整個檔案夾的筆記", "你的字體，淺色或深色"],
]

let size = NSSize(width: 2880, height: 1800)

func render(scene: String, caption: String, to file: URL) throws {
    guard let window = NSImage(contentsOf: raw.appending(path: "raw-\(scene).png")) else { throw CocoaError(.fileReadCorruptFile) }
    let dark = scene == "4-dark"
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let colors: [NSColor] = dark
        ? [NSColor(srgbRed: 0.07, green: 0.08, blue: 0.15, alpha: 1), NSColor(srgbRed: 0.17, green: 0.15, blue: 0.27, alpha: 1)]
        : [NSColor(srgbRed: 0.92, green: 0.93, blue: 0.99, alpha: 1), NSColor(srgbRed: 0.79, green: 0.82, blue: 0.96, alpha: 1)]
    NSGradient(colors: colors)!.draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // Caption, shrunk to fit if a language needs more room.
    var fontSize: CGFloat = 112
    var attributes: [NSAttributedString.Key: Any] = [:]
    var textSize = NSSize.zero
    repeat {
        attributes = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: dark ? NSColor.white : NSColor(srgbRed: 0.10, green: 0.11, blue: 0.20, alpha: 1),
            .kern: -fontSize * 0.02,
        ]
        textSize = (caption as NSString).size(withAttributes: attributes)
        fontSize -= 4
    } while textSize.width > size.width - 360
    let captionCenter: CGFloat = 158
    (caption as NSString).draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: size.height - captionCenter - textSize.height / 2), withAttributes: attributes)

    // The window, 2360 × 1462 pixels, with a soft shadow.
    let frame = NSRect(x: (size.width - 2360) / 2, y: size.height - 260 - 1462, width: 2360, height: 1462)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.22)
    shadow.shadowBlurRadius = 70
    shadow.shadowOffset = NSSize(width: 0, height: -24)
    shadow.set()
    window.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try rep.representation(using: .png, properties: [:])!.write(to: file)
}

for (language, texts) in captions.sorted(by: { $0.key < $1.key }) {
    for (scene, caption) in zip(scenes, texts) {
        try render(scene: scene, caption: caption, to: out.appending(path: "\(language)/\(scene).png"))
    }
    print("ok", language)
}
