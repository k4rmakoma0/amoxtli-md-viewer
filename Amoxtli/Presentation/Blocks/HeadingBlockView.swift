import SwiftUI

struct HeadingBlockView: View {
    let level: Int
    let content: InlineText

    var body: some View {
        MarkdownText(content: content, role: .heading(level: level))
            .padding(.top, level <= 2 ? BlockMetrics.spacing : BlockMetrics.nestedSpacing)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHeading(headingLevel)
    }

    private var headingLevel: AccessibilityHeadingLevel {
        switch level {
        case 1: .h1
        case 2: .h2
        case 3: .h3
        case 4: .h4
        case 5: .h5
        default: .h6
        }
    }
}
