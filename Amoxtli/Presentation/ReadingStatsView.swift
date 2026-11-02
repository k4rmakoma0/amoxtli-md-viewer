import SwiftUI

/// Word count and reading time in the bottom-right corner, like a status bar.
struct ReadingStatsView: View {
    let stats: ReadingStats

    var body: some View {
        HStack(spacing: 6) {
            Text("\(stats.wordCount) palabras")
            Text(verbatim: "·")
                .accessibilityHidden(true)
            readingTime
        }
        .font(.footnote)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }

    private var readingTime: Text {
        if let minutes = stats.readingMinutes {
            Text("\(minutes) min de lectura")
        } else {
            Text("menos de 1 min de lectura")
        }
    }
}

#Preview {
    VStack {
        ReadingStatsView(stats: ReadingStats(wordCount: 116))
        ReadingStatsView(stats: ReadingStats(wordCount: 1_250))
    }
}
