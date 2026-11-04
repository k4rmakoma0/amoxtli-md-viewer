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
        numbering(of: text).markers
    }

    /// The markers, and the numbering as it stands after the last paragraph, which numbers an
    /// empty last line that only exists in the style kept for typing.
    static func numbering(of text: NSAttributedString) -> (markers: [Int: [RichListMarker]], end: Numbering) {
        var result: [Int: [RichListMarker]] = [:]
        var numbering = Numbering()
        for paragraph in text.paragraphRanges(in: NSRange(location: 0, length: text.length)) {
            let markers = numbering.markers(for: text.paragraphKind(at: paragraph.location)?.containers ?? [])
            if !markers.isEmpty { result[paragraph.location] = markers }
        }
        return (result, numbering)
    }

    /// Numbers items in document order: each new item takes the next number of its list.
    struct Numbering {
        private var counts: [Int: Int] = [:]
        private var previous: [RichContainer] = []

        /// The markers of a paragraph with these containers, one for each item it starts.
        mutating func markers(for containers: [RichContainer]) -> [RichListMarker] {
            var markers: [RichListMarker] = []
            for (depth, container) in containers.enumerated() {
                guard case .listItem(let item) = container else { continue }
                let isNewItem = !(previous.indices.contains(depth) && previous[depth] == container)
                guard isNewItem else { continue }
                let index = counts[item.listID, default: 0] + 1
                counts[item.listID] = index
                let level = containers.prefix(depth).filter { if case .listItem = $0 { true } else { false } }.count
                let text = item.isOrdered ? "\(item.start + index - 1)." : RichListMarker.bullet(atLevel: level)
                markers.append(RichListMarker(depth: depth, level: level, index: index, text: text))
            }
            previous = containers
            return markers
        }
    }

    fileprivate static func bullet(atLevel level: Int) -> String {
        ["•", "◦", "▪"][level % 3]
    }
}
