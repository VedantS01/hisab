import SwiftUI
import Charts
import HisabCore

struct TrendChart: View {
    let trend: [MonthStats]
    let selected: YearMonth

    var body: some View {
        HisabCard {
            Text("6-month trend")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Chart(trend, id: \.month) { stats in
                BarMark(
                    x: .value("Month", stats.month.displayName),
                    y: .value("Spend", Double(stats.spendPaise) / 100.0)
                )
                .foregroundStyle(stats.month == selected ? HisabTheme.khataRed : HisabTheme.ink.opacity(0.3))
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let rupees = value.as(Double.self) {
                            Text(compact(rupees))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
    }

    private func compact(_ rupees: Double) -> String {
        switch rupees {
        case 10_000_000...: String(format: "%.1fCr", rupees / 10_000_000)
        case 100_000...: String(format: "%.1fL", rupees / 100_000)
        case 1_000...: String(format: "%.0fk", rupees / 1_000)
        default: String(format: "%.0f", rupees)
        }
    }
}
