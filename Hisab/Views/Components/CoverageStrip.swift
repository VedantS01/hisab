import SwiftUI
import HisabCore

struct CoverageStrip: View {
    let grid: CoverageGrid
    let month: YearMonth

    var body: some View {
        HisabCard {
            Text("Statements for \(month.displayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(Source.allCases) { source in
                    chip(source)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(_ source: Source) -> some View {
        let present = isPresent(source)
        HStack(spacing: 5) {
            Image(systemName: present ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(present ? HisabTheme.sona : Color.secondary)
            Text(shortName(source))
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(present ? HisabTheme.primaryText : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(present ? HisabTheme.sona.opacity(0.12) : Color.clear)
                .strokeBorder(present ? HisabTheme.sona.opacity(0.5) : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1, dash: present ? [] : [4]))
        )
    }

    private func isPresent(_ source: Source) -> Bool {
        if case .present = grid.state(month: month, source: source) { return true }
        return false
    }

    private func shortName(_ source: Source) -> String {
        switch source {
        case .gpay: "GPay"
        case .paytm: "Paytm"
        case .hdfc: "HDFC"
        case .idfc: "IDFC"
        }
    }
}
