import AppKit

/// The fills and lines the editors draw behind text, in both editors. The system's fills are
/// too faint for these on a dark background, so each has its own light and dark value, and a
/// stronger one when Increase Contrast is on.
nonisolated enum SurfaceColors {
    /// Behind inline code and code blocks.
    static let codeBackground = adaptive("codeBackground", light: 0.075, dark: 0.13, increasedContrast: 0.16)
    /// The header row of a table.
    static let tableHeader = adaptive("tableHeader", light: 0.05, dark: 0.08, increasedContrast: 0.12)
    /// The lines between the cells of a table.
    static let tableBorder = adaptive("tableBorder", light: 0.2, dark: 0.26, increasedContrast: 0.5)

    /// Black over a light background and white over a dark one, at the given opacity.
    private static func adaptive(_ name: String, light: CGFloat, dark: CGFloat, increasedContrast: CGFloat) -> NSColor {
        NSColor.adaptive(name) { isDark, isHighContrast in
            let alpha = isHighContrast ? increasedContrast : (isDark ? dark : light)
            return NSColor(white: isDark ? 1 : 0, alpha: alpha)
        }
    }
}

nonisolated extension NSColor {
    /// A color that resolves for the appearance it is drawn in, light or dark, with or
    /// without Increase Contrast.
    static func adaptive(_ name: String, color: @escaping @Sendable (_ isDark: Bool, _ isHighContrast: Bool) -> NSColor) -> NSColor {
        NSColor(name: "dev.alananaya.amoxtli.\(name)") { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let isHighContrast = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
            return color(isDark, isHighContrast)
        }
    }
}
