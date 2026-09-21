import SwiftUI
import HisabCore

/// The "For you" strip: at most five neutral observations, furniture rather
/// than notification — no badges, no unread counts, no entrance animation.
struct InsightStrip: View {
    let insights: [Insight]
    let onOpen: (Insight) -> Void
    let onDismiss: (Insight) -> Void
    let onMute: (Insight) -> Void

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("For you")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HisabTheme.primaryText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(insights) { insight in
                            InsightCard(insight: insight,
                                        onOpen: { onOpen(insight) },
                                        onDismiss: { onDismiss(insight) },
                                        onMute: { onMute(insight) })
                                .containerRelativeFrame(.horizontal) { width, _ in
                                    width * 0.85
                                }
                        }
                    }
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

private struct InsightCard: View {
    let insight: Insight
    let onOpen: () -> Void
    let onDismiss: () -> Void
    let onMute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(caption)
                Spacer()
                if insight.kind != .committedSpend {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(accent)

            Text(insight.headline)
                .font(.headline)
                .foregroundStyle(HisabTheme.primaryText)
            Text(insight.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(HisabTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            if insight.mute != nil {
                Button("Don't show insights like this", action: onMute)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption). \(insight.headline). \(insight.detail)")
        .accessibilityAddTraits(.isButton)
    }

    private var caption: String {
        switch insight.kind {
        case .trend: "TREND"
        case .recurringNew, .recurringChanged: "RECURRING"
        case .committedSpend: "COMMITTED"
        case .possibleDuplicate, .outlierAmount: "UNUSUAL"
        }
    }

    private var icon: String {
        switch insight.kind {
        // Display-only: the core copy starts with "up "/"down ", pinned by
        // the parity fixture, so the arrow can't drift from the sentence.
        case .trend: insight.detail.hasPrefix("down") ? "arrow.down.right" : "arrow.up.right"
        case .recurringNew, .recurringChanged: "arrow.triangle.2.circlepath"
        case .committedSpend: "calendar"
        case .possibleDuplicate: "doc.on.doc"
        case .outlierAmount: "exclamationmark.triangle"
        }
    }

    private var accent: Color {
        switch insight.kind {
        case .trend: insight.detail.hasPrefix("down") ? HisabTheme.hara : HisabTheme.khataRed
        case .recurringNew, .recurringChanged: HisabTheme.primaryText
        case .committedSpend, .possibleDuplicate, .outlierAmount: HisabTheme.sona
        }
    }
}
