import AppKit

/// The bullet or number of a list item, worked out from the paragraphs' kinds: items are
/// numbered in the order they appear, so they renumber as items come and go.
nonisolated struct RichListMarker: Equatable {
    /// Index of the item's container in the paragraph's containers.
    let depth: Int
    /// How many lists the item is nested in.
    let level: Int
    /// The item's position in its list, from 1.
    let index: Int
    let text: String

    /// The markers of every paragraph that starts an item, by the paragraph's location.
    static func markers(in text: NSAttributedString) -> [Int: [RichListMarker]] {
        var result: [Int: [RichListMarker]] = [:]
        var counts: [Int: Int] = [:]
        var previous: [RichContainer] = []
        for paragraph in text.paragraphRanges(in: NSRange(location: 0, length: text.length)) {
            let containers = text.paragraphKind(at: paragraph.location)?.containers ?? []
            for (depth, container) in containers.enumerated() {
                guard case .listItem(let item) = container else { continue }
                let isNewItem = !(previous.indices.contains(depth) && previous[depth] == container)
                guard isNewItem else { continue }
                let index = counts[item.listID, default: 0] + 1
                counts[item.listID] = index
                let level = containers.prefix(depth).filter { if case .listItem = $0 { true } else { false } }.count
                let text = item.isOrdered ? "\(item.start + index - 1)." : bullet(atLevel: level)
                result[paragraph.location, default: []].append(RichListMarker(depth: depth, level: level, index: index, text: text))
            }
            previous = containers
        }
        return result
    }

    private static func bullet(atLevel level: Int) -> String {
        ["•", "◦", "▪"][level % 3]
    }
}
