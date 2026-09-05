import SwiftUI
import HisabCore

struct HeroCard: View {
    let stats: MonthStats
    let previous: MonthStats

    private var deltaPercent: Int? {
        guard previous.spendPaise > 0 else { return nil }
        return Int((stats.spendPaise - previous.spendPaise) * 100 / previous.spendPaise)
    }

    var body: some View {
        HisabCard {
            Text("Spent in \(stats.month.displayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Money.formatPaise(stats.spendPaise))
                    .font(.system(size: 38, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(HisabTheme.primaryText)
                if let delta = deltaPercent {
                    deltaPill(delta)
                }
            }
            Divider()
            row("Income", Money.formatPaise(stats.incomePaise), HisabTheme.hara)
            row("Net", Money.formatPaise(stats.netPaise, signed: true),
                stats.netPaise >= 0 ? HisabTheme.hara : HisabTheme.khataRed)
            Text(basisFootnote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func deltaPill(_ delta: Int) -> some View {
        Label("\(abs(delta))%", systemImage: delta >= 0 ? "arrow.up" : "arrow.down")
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((delta >= 0 ? HisabTheme.khataRed : HisabTheme.hara).opacity(0.15), in: Capsule())
            .foregroundStyle(delta >= 0 ? HisabTheme.khataRed : HisabTheme.hara)
    }

    private func row(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(color)
        }
    }

    private var basisFootnote: String {
        switch stats.basis {
        case .bank: "from bank statements"
        case .paymentApps: "from payment apps (no bank statement yet)"
        case .none: "no data for this month"
        }
    }
}
