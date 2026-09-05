import SwiftUI
import HisabCore

struct CategoryBars: View {
    let breakdown: [(category: String, paise: Int64)]

    var body: some View {
        if !breakdown.isEmpty {
            HisabCard {
                Text("Where it went")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                let maxPaise = breakdown.map(\.paise).max() ?? 1
                ForEach(Array(breakdown.enumerated()), id: \.offset) { index, entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.category)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(HisabTheme.primaryText)
                            Spacer()
                            Text(Money.formatPaise(entry.paise))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [HisabTheme.khataRed, HisabTheme.sona],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, geo.size.width * CGFloat(entry.paise) / CGFloat(maxPaise)))
                                .opacity(entry.category == "Other" ? 0.45 : 1)
                        }
                        .frame(height: 7)
                    }
                }
            }
        }
    }
}
