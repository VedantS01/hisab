import Foundation

/// Lightweight document projection the app layer feeds into grid derivation.
public struct DocumentSummary: Sendable {
    public let id: UUID
    public let source: Source
    public let period: DatePeriod

    public init(id: UUID, source: Source, period: DatePeriod) {
        self.id = id
        self.source = source
        self.period = period
    }
}

public enum CellState: Equatable, Sendable {
    case present(documentIDs: [UUID])
    case awaiting
}

/// The month × source presence grid. Months are derived, never stored: the union of every
/// document's covered months and manual pins, gap-filled so interior holes stay visible.
public struct CoverageGrid: Sendable {
    public let months: [YearMonth]  // newest first
    private let cells: [YearMonth: [Source: [UUID]]]

    public func state(month: YearMonth, source: Source) -> CellState {
        if let ids = cells[month]?[source], !ids.isEmpty {
            return .present(documentIDs: ids)
        }
        return .awaiting
    }

    public static func derive(documents: [DocumentSummary], pinnedMonths: Set<YearMonth>) -> CoverageGrid {
        var cells: [YearMonth: [Source: [UUID]]] = [:]
        var touched = pinnedMonths
        for doc in documents {
            for month in doc.period.months {
                touched.insert(month)
                cells[month, default: [:]][doc.source, default: []].append(doc.id)
            }
        }
        guard let lo = touched.min(), let hi = touched.max() else {
            return CoverageGrid(months: [], cells: [:])
        }
        let months = YearMonth.months(from: lo, through: hi).reversed()
        return CoverageGrid(months: Array(months), cells: cells)
    }
}
