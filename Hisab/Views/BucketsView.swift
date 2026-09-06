import SwiftUI
import SwiftData
import HisabCore

struct BucketsView: View {
    @Environment(\.modelContext) private var context
    @State private var sheetTarget: SheetTarget?
    @State private var showPinPicker = false
    @State private var refreshToken = 0

    private struct SheetTarget: Identifiable {
        let month: YearMonth
        let source: Source
        let documentIDs: [UUID]
        var id: String { "\(month)-\(source.rawValue)" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                gridContent
                    .padding(16)
            }
            .background(HisabTheme.background)
            .navigationTitle("Buckets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPinPicker = true
                    } label: {
                        Label("Pin month", systemImage: "pin")
                    }
                }
            }
            .sheet(item: $sheetTarget, onDismiss: { refreshToken += 1 }) { target in
                DocumentListSheet(month: target.month, source: target.source, documentIDs: target.documentIDs)
            }
            .sheet(isPresented: $showPinPicker, onDismiss: { refreshToken += 1 }) {
                PinMonthSheet()
            }
        }
    }

    @ViewBuilder
    private var gridContent: some View {
        let grid = Queries.coverageGrid(context)
        let _ = refreshToken

        if grid.months.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 44))
                    .foregroundStyle(HisabTheme.khataRed)
                Text("No months yet — import a statement or pin a month to start tracking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 100)
        } else {
            VStack(spacing: 8) {
                header
                ForEach(grid.months, id: \.self) { month in
                    row(month: month, grid: grid)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Month")
                .frame(width: 76, alignment: .leading)
            ForEach(Source.allCases) { source in
                Text(shortName(source))
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func row(month: YearMonth, grid: CoverageGrid) -> some View {
        HStack(spacing: 8) {
            Text(month.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(HisabTheme.primaryText)
                .frame(width: 76, alignment: .leading)
            ForEach(Source.allCases) { source in
                cell(month: month, source: source, state: grid.state(month: month, source: source))
            }
        }
    }

    @ViewBuilder
    private func cell(month: YearMonth, source: Source, state: CellState) -> some View {
        switch state {
        case .present(let ids):
            Button {
                sheetTarget = SheetTarget(month: month, source: source, documentIDs: ids)
            } label: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(HisabTheme.sona.opacity(0.16))
                    .strokeBorder(HisabTheme.sona.opacity(0.6), lineWidth: 1)
                    .frame(height: 40)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(HisabTheme.sona)
                    }
            }
            .buttonStyle(.plain)
        case .awaiting:
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                .frame(height: 40)
                .frame(maxWidth: .infinity)
        }
    }

    private func shortName(_ source: Source) -> String {
        switch source {
        case .gpay: "GPay"
        case .paytm: "Paytm"
        case .bhim: "BHIM"
        case .hdfc: "HDFC"
        case .idfc: "IDFC"
        }
    }
}

struct PinMonthSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var year = YearMonth(date: Date()).year
    @State private var month = YearMonth(date: Date()).month

    var body: some View {
        NavigationStack {
            Form {
                Picker("Year", selection: $year) {
                    ForEach(2020...2032, id: \.self) { Text(String($0)).tag($0) }
                }
                Picker("Month", selection: $month) {
                    ForEach(1...12, id: \.self) {
                        Text(YearMonth(year: 2000, month: $0).displayName.prefix(3)).tag($0)
                    }
                }
            }
            .navigationTitle("Pin a month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pin") {
                        context.insert(PinnedMonth(YearMonth(year: year, month: month)))
                        try? context.save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
