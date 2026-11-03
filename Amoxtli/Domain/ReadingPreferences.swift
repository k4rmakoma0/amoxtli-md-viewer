import Foundation

/// The typefaces people can choose from. All of them are the system's own designs, so they look
/// at home in macOS and every language the system supports is covered.
nonisolated enum ReadingFont: String, CaseIterable, Sendable {
    case system, serif, monospaced, rounded
}

/// Size of body text, in points. Moves through fixed steps, like Make Text Bigger in other apps,
/// and every other size in the document scales with it.
nonisolated struct TextSize: RawRepresentable, Hashable, Sendable {
    static let steps = [10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 32]
    /// The system's body size.
    static let standard = TextSize(points: 13)

    let points: Int

    /// Stored values come back as the closest step, so an edited or outdated preference can't
    /// produce a size the app doesn't offer.
    init(points: Int) {
        self.points = Self.steps.min { abs($0 - points) < abs($1 - points) } ?? 13
    }

    init(rawValue: Int) {
        self.init(points: rawValue)
    }

    var rawValue: Int { points }

    /// How much bigger than the standard size, for sizes derived from body text.
    var scale: Double { Double(points) / Double(Self.standard.points) }

    /// `nil` at the largest step.
    var larger: TextSize? {
        Self.steps.first { $0 > points }.map(TextSize.init(points:))
    }

    /// `nil` at the smallest step.
    var smaller: TextSize? {
        Self.steps.last { $0 < points }.map(TextSize.init(points:))
    }
}
