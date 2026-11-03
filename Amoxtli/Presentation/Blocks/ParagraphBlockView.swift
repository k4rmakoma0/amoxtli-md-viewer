import SwiftUI

struct ParagraphBlockView: View {
    let content: InlineText

    @Environment(\.typography) private var typography

    var body: some View {
        MarkdownText(content: content, role: .body)
            .alignedToFirstBaseline(typography)
    }
}
