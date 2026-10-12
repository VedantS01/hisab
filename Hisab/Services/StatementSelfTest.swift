#if DEBUG
import Foundation
import HisabCore

/// `--statement-selftest`: the on-device half of `ProposedMappingTests`' live
/// test, for a phone, where SwiftPM tests cannot run. Apple's model names the
/// columns of a table the rules refuse, and the reading must close the
/// balance chain. Read-only: nothing touches the store.
enum StatementSelfTest {
    private static let csv = """
        XYZ BANK LTD
        Date,Details,Ref,Amount,Balance
        Opening Balance,,,,1000.00
        01/04/2026,POS COFFEE,R1,100.00,900.00
        02/04/2026,SALARY ACME,R2,50.00,950.00
        03/04/2026,UPI GROCER,R3,200.00,750.00
        Closing Balance,,,350.00,750.00
        """

    static func run() async -> String {
        guard #available(iOS 26, *) else { return "STATEMENT-SELFTEST needs iOS 26" }
        guard OnDeviceColumnReader.isAvailable else { return "STATEMENT-SELFTEST model unavailable" }
        guard let table = NormalizedTable.from(data: Data(csv.utf8), filename: "selftest.csv", password: nil) else {
            return "STATEMENT-SELFTEST no table"
        }
        let start = Date()
        let read = await ProposedMapping.read(table: table, proposer: OnDeviceColumnReader())
        let seconds = Date().timeIntervalSince(start)
        guard let read else { return String(format: "STATEMENT-SELFTEST refused (%.1f s)", seconds) }
        let right = read.transactions.map(\.direction) == [.debit, .credit, .debit]
            && read.transactions.map(\.amountPaise) == [100_00, 50_00, 200_00]
        return String(format: "STATEMENT-SELFTEST %@ %d rows (%.1f s)", right ? "read" : "MISREAD",
                      read.transactions.count, seconds)
    }
}
#endif
