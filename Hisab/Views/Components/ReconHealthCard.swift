import SwiftUI
import SwiftData
import HisabCore

struct ReconHealthCard: View {
    @Environment(\.modelContext) private var context
    let month: YearMonth

    var body: some View {
        let (app, bank) = Queries.reconTxns(context, month: month)
        if !app.isEmpty && !bank.isEmpty {
            let matches = Queries.matches(context, month: month)
            let matchedApp = Set(matches.map(\.appUUID))
            let unmatched = app.filter { !matchedApp.contains($0.id) }.count
            let percent = app.isEmpty ? 0 : (app.count - unmatched) * 100 / app.count

            NavigationLink {
                ReconciliationView(initialMonth: month)
            } label: {
                HisabCard {
                    HStack(spacing: 16) {
                        ring(percent: percent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reconciliation")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(percent)% matched")
                                .font(.headline)
                                .foregroundStyle(HisabTheme.primaryText)
                            if unmatched > 0 {
                                Text("\(unmatched) app payment\(unmatched == 1 ? "" : "s") missing from bank")
                                    .font(.caption)
                                    .foregroundStyle(HisabTheme.khataRed)
                            } else {
                                Text("Everything accounted for")
                                    .font(.caption)
                                    .foregroundStyle(HisabTheme.hara)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func ring(percent: Int) -> some View {
        ZStack {
            Circle()
                .stroke(HisabTheme.ink.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(percent == 100 ? HisabTheme.hara : HisabTheme.sona,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)")
                .font(.caption.bold())
                .monospacedDigit()
                .foregroundStyle(HisabTheme.primaryText)
        }
        .frame(width: 48, height: 48)
    }
}
