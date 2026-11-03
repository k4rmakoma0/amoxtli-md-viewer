import AppKit
import SwiftUI

/// The typeface and size people chose, turned into the fonts of each kind of text. It applies to
/// the source and to the formatted document alike.
nonisolated struct Typography: Equatable {
    var font: ReadingFont = .system
    var size: TextSize = .standard

    static let fontKey = "readingFont"
    static let sizeKey = "textSize"

    var body: NSFont {
        font(ofSize: CGFloat(size.points))
    }

    /// Code keeps a monospaced font whatever the typeface, so columns still line up.
    var code: NSFont {
        .monospacedSystemFont(ofSize: CGFloat(size.points), weight: .regular)
    }

    func heading(level: Int) -> NSFont {
        font(ofSize: CGFloat(size.points) * Self.headingScale(level)).withTraits(.bold)
    }

    /// The system's text styles, relative to body text: large title, title 1 to 3, headline and
    /// subheadline.
    private static func headingScale(_ level: Int) -> CGFloat {
        switch level {
        case 1: 26 / 13
        case 2: 22 / 13
        case 3: 17 / 13
        case 4: 15 / 13
        case 5: 1
        default: 11 / 13
        }
    }

    private func font(ofSize size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size)
        guard let descriptor = system.fontDescriptor.withDesign(font.design) else { return system }
        return NSFont(descriptor: descriptor, size: size) ?? system
    }
}

nonisolated extension ReadingFont {
    var design: NSFontDescriptor.SystemDesign {
        switch self {
        case .system: .default
        case .serif: .serif
        case .monospaced: .monospaced
        case .rounded: .rounded
        }
    }
}

extension ReadingFont {
    var title: LocalizedStringKey {
        switch self {
        case .system: "Sistema"
        case .serif: "Serif"
        case .monospaced: "Monoespaciada"
        case .rounded: "Redondeada"
        }
    }
}

extension EnvironmentValues {
    @Entry var typography = Typography()
}

/// Reads the saved choice, for the views that apply it and the controls that change it.
struct TypographyPreferences: DynamicProperty {
    @AppStorage(Typography.fontKey) var font = ReadingFont.system
    @AppStorage(Typography.sizeKey) var size = TextSize.standard

    var typography: Typography {
        Typography(font: font, size: size)
    }

    func makeLarger() {
        if let larger = size.larger { size = larger }
    }

    func makeSmaller() {
        if let smaller = size.smaller { size = smaller }
    }

    func resetSize() {
        size = .standard
    }
}
