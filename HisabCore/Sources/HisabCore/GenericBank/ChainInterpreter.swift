import Foundation

/// Which cell means what in a bank-statement body row. Exactly one amount
/// convention applies: separate debit/credit columns, a single signed amount,
/// an unsigned amount qualified by a DR/CR column, or an unsigned amount whose
/// direction only the balance chain can reveal (`amountIsUnsigned`).
public struct ColumnMapping: Equatable, Sendable {
    public var date: Int
    public var narration: Int
    public var reference: Int?
    public var debit: Int?
    public var credit: Int?
    public var amount: Int?
    public var drcr: Int?
    public var balance: Int
    public var amountIsUnsigned: Bool
    public var dateFormat: String

    public init(date: Int, narration: Int, reference: Int? = nil,
                debit: Int? = nil, credit: Int? = nil,
                amount: Int? = nil, drcr: Int? = nil,
                balance: Int, amountIsUnsigned: Bool = false, dateFormat: String) {
        self.date = date
        self.narration = narration
        self.reference = reference
        self.debit = debit
        self.credit = credit
        self.amount = amount
        self.drcr = drcr
        self.balance = balance
        self.amountIsUnsigned = amountIsUnsigned
        self.dateFormat = dateFormat
    }
}

public enum ChainOutcome: Sendable, Equatable {
    case validated([ParsedTransaction])
    case broken(rowIndex: Int, detail: String)
}

/// Applies a mapping to body rows and accepts the result only when the running
/// balance closes to the paisa on every row. When the columns assert a
/// direction, the chain must agree — disagreement is a break, not a warning.
public enum ChainInterpreter {
    public static func interpret(rows: [[String]], mapping: ColumnMapping,
                                 openingBalancePaise: Int64? = nil) -> ChainOutcome {
        let first = run(rows: rows, mapping: mapping,
                        openingBalance: openingBalancePaise, openingDirection: .debit)
        if mapping.amountIsUnsigned, mapping.drcr == nil, openingBalancePaise == nil {
            // Row 1 has no predecessor to anchor its direction; try both and let
            // the rest of the chain arbitrate.
            let second = run(rows: rows, mapping: mapping,
                             openingBalance: nil, openingDirection: .credit)
            switch (first, second) {
            case (.validated(let a), .validated(let b)):
                return a == b ? .validated(a)
                              : .broken(rowIndex: 0, detail: "ambiguous opening direction")
            case (.validated, .broken): return first
            case (.broken, .validated): return second
            case (.broken, .broken): return first
            }
        }
        return first
    }

    private static func run(rows: [[String]], mapping: ColumnMapping,
                            openingBalance: Int64?, openingDirection: Direction) -> ChainOutcome {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = mapping.dateFormat

        var transactions: [ParsedTransaction] = []
        var previousBalance = openingBalance

        for (index, row) in rows.enumerated() {
            func cell(_ column: Int?) -> String {
                guard let column, column >= 0, column < row.count else { return "" }
                return row[column]
            }

            let dateText = cell(mapping.date)
            guard let date = formatter.date(from: dateText) else {
                return .broken(rowIndex: index, detail: "unreadable date '\(dateText)'")
            }
            let balanceText = cell(mapping.balance)
            guard let balance = Money.signedPaise(fromDecimalString: balanceText) else {
                return .broken(rowIndex: index, detail: "unreadable balance '\(balanceText)'")
            }

            var amount: Int64
            var assertedDirection: Direction?
            if let debitColumn = mapping.debit, let creditColumn = mapping.credit {
                let debitText = cell(debitColumn)
                let creditText = cell(creditColumn)
                switch (debitText.isEmpty, creditText.isEmpty) {
                case (false, true):
                    guard let value = Money.signedPaise(fromDecimalString: debitText) else {
                        return .broken(rowIndex: index, detail: "unreadable debit '\(debitText)'")
                    }
                    amount = value
                    assertedDirection = .debit
                case (true, false):
                    guard let value = Money.signedPaise(fromDecimalString: creditText) else {
                        return .broken(rowIndex: index, detail: "unreadable credit '\(creditText)'")
                    }
                    amount = value
                    assertedDirection = .credit
                default:
                    return .broken(rowIndex: index,
                                   detail: "expected exactly one of debit/credit, got '\(debitText)'/'\(creditText)'")
                }
            } else if let amountColumn = mapping.amount {
                let amountText = cell(amountColumn)
                guard let value = Money.signedPaise(fromDecimalString: amountText) else {
                    return .broken(rowIndex: index, detail: "unreadable amount '\(amountText)'")
                }
                if let drcrColumn = mapping.drcr {
                    switch cell(drcrColumn).lowercased() {
                    case "dr": assertedDirection = .debit
                    case "cr": assertedDirection = .credit
                    default:
                        return .broken(rowIndex: index, detail: "unreadable DR/CR '\(cell(drcrColumn))'")
                    }
                    amount = abs(value)
                } else if mapping.amountIsUnsigned {
                    amount = abs(value)
                    assertedDirection = nil
                } else {
                    amount = abs(value)
                    assertedDirection = value < 0 ? .debit : .credit
                }
            } else {
                return .broken(rowIndex: index, detail: "mapping declares no amount columns")
            }

            guard amount > 0 else {
                return .broken(rowIndex: index, detail: "non-positive amount")
            }

            let direction: Direction
            if let previous = previousBalance {
                if previous - amount == balance {
                    direction = .debit
                } else if previous + amount == balance {
                    direction = .credit
                } else {
                    return .broken(rowIndex: index,
                                   detail: "balance chain break: \(previous) ±\(amount) ≠ \(balance)")
                }
                if let asserted = assertedDirection, asserted != direction {
                    return .broken(rowIndex: index,
                                   detail: "columns say \(asserted.rawValue), chain says \(direction.rawValue)")
                }
            } else {
                direction = assertedDirection ?? openingDirection
            }

            let narration = cell(mapping.narration)
            let referenceCell = cell(mapping.reference)
            let reference = referenceCell.isEmpty
                ? SyntheticRef.make(balancePaise: balance, date: date, amountPaise: amount)
                : referenceCell
            transactions.append(ParsedTransaction(date: date, amountPaise: amount,
                                                  direction: direction,
                                                  counterparty: narration,
                                                  reference: reference,
                                                  narration: narration))
            previousBalance = balance
        }

        return .validated(transactions)
    }
}
