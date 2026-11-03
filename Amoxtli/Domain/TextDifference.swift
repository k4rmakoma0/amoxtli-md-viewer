import Foundation

/// The smallest single replacement that turns one text into another, in UTF-16 offsets. Applying
/// only that keeps the rest of an editor untouched: its selection, scroll position and styling.
nonisolated struct TextDifference: Equatable, Sendable {
    /// Range in the old text.
    let range: NSRange
    let replacement: String

    init(range: NSRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }

    init(from old: String, to new: String) {
        let before = old as NSString
        let after = new as NSString
        let shorter = min(before.length, after.length)
        var prefix = 0
        while prefix < shorter, before.character(at: prefix) == after.character(at: prefix) {
            prefix += 1
        }
        var suffix = 0
        while suffix < shorter - prefix,
              before.character(at: before.length - 1 - suffix) == after.character(at: after.length - 1 - suffix) {
            suffix += 1
        }
        // Never split a character made of two UTF-16 units.
        if prefix > 0, UTF16.isLeadSurrogate(before.character(at: prefix - 1)) { prefix -= 1 }
        if suffix > 0, UTF16.isTrailSurrogate(before.character(at: before.length - suffix)) { suffix -= 1 }
        range = NSRange(location: prefix, length: before.length - prefix - suffix)
        replacement = after.substring(with: NSRange(location: prefix, length: after.length - prefix - suffix))
    }

    var isEmpty: Bool {
        range.length == 0 && replacement.isEmpty
    }

    /// Where a selection ends up: untouched before the change, shifted after it, and at the end
    /// of the new text when it was inside what changed.
    func adjusting(_ selection: NSRange) -> NSRange {
        let delta = replacement.utf16.count - range.length
        let changeEnd = NSMaxRange(range)
        if selection.location >= changeEnd {
            return NSRange(location: selection.location + delta, length: selection.length)
        }
        if NSMaxRange(selection) <= range.location {
            return selection
        }
        return NSRange(location: range.location + replacement.utf16.count, length: 0)
    }
}
