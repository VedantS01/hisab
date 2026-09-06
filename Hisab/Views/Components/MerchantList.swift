import SwiftUI
import HisabCore

struct MerchantList: View {
    let merchants: [(merchant: String, paise: Int64)]

    var body: some View {
        if !merchants.isEmpty {
            HisabCard {
                Text("Top merchants")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(Array(merchants.enumerated()), id: \.offset) { index, entry in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .monospacedDigit()
                            .frame(width: 22, height: 22)
                            .background(HisabTheme.sona.opacity(0.2), in: Circle())
                            .foregroundStyle(HisabTheme.primaryText)
                        Text(entry.merchant)
                            .font(.subheadline)
                            .foregroundStyle(HisabTheme.primaryText)
                            .lineLimit(1)
                        Spacer()
                        Text(Money.formatPaise(entry.paise))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(HisabTheme.primaryText)
                    }
                }
            }
        }
    }
}
