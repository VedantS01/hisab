import SwiftUI
import SwiftData
import HisabCore

struct RecentTxns: View {
    @Query(sort: \StoredTransaction.date, order: .reverse) private var allTxns: [StoredTransaction]
    @Query private var matchRows: [StoredMatch]
    let month: YearMonth

    var body: some View {
        let txns = Array(Queries.visible(allTxns, matches: matchRows)
            .filter { $0.month == month }.prefix(10))
        if !txns.isEmpty {
            HisabCard {
                Text("Recent transactions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(txns, id: \.uuid) { txn in
                    TxnRow(txn: txn)
                    if txn.uuid != txns.last?.uuid {
                        Divider()
                    }
                }
            }
        }
    }
}

struct TxnRow: View {
    let txn: StoredTransaction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: HisabTheme.sourceGlyph(txn.source))
                .foregroundStyle(txn.source.kind == .bank ? HisabTheme.ink.opacity(0.7) : HisabTheme.khataRed)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(txn.counterparty)
                    .font(.subheadline)
                    .foregroundStyle(HisabTheme.primaryText)
                    .lineLimit(1)
                Text(txn.date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HisabTheme.amountText(txn.amountPaise, direction: txn.direction)
                .font(.subheadline.weight(.semibold))
        }
    }
}
