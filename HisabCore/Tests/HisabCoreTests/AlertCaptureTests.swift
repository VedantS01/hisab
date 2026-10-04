import XCTest
@testable import HisabCore

/// Pins `AlertCapture` (extractor output -> memo / ledger row) and
/// `SelfTransfers.alerts` against `alert-capture.json`, which `capture_test.dart`
/// reads too. Expected hashes were computed from the documented canonical
/// strings, independently of this code.
final class AlertCaptureTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Alert: Decodable {
            var is_txn: Bool
            var direction: String?
            var amount_paise: Int64?
            var ref: String?
            var payee: String?
            var vpa: String?
            var own_acct_tail: String?
            var cpty_acct_tail: String?
            var date_iso: String?
        }
        struct Memo: Decodable, Equatable {
            var amountPaise: Int64
            var direction: String
            var payee: String
            var vpa: String?
            var accountTail: String?
            var dateISO: String
            var captureHash: String
        }
        struct Ledger: Decodable, Equatable {
            var amountPaise: Int64
            var direction: String
            var counterparty: String
            var reference: String
            var narration: String
            var dateISO: String
            var contentHash: String
        }
        struct Case: Decodable {
            var name: String
            var receivedAt: String
            var alert: Alert
            var memo: Memo?
            var ledger: Ledger?
        }
        struct SelfTransferCase: Decodable {
            var name: String
            var bankRefs: [String]
            var rows: [[String]]
            var expected: [String]
        }
        var cases: [Case]
        var selfTransfers: [SelfTransferCase]
    }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "alert-capture", withExtension: "json",
                                                  subdirectory: "Fixtures"), "missing fixture alert-capture.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testMemoAndLedgerRowMatchFixture() throws {
        let iso = ISO8601DateFormatter()
        for c in try fixture().cases {
            let received = try XCTUnwrap(iso.date(from: c.receivedAt), c.name)
            let a = c.alert
            let alert = ExtractedAlert(isTransaction: a.is_txn, direction: a.direction.flatMap(Direction.init(rawValue:)),
                                       amountPaise: a.amount_paise, ref: a.ref, payee: a.payee, vpa: a.vpa,
                                       ownAccountTail: a.own_acct_tail, counterpartyAccountTail: a.cpty_acct_tail,
                                       dateISO: a.date_iso, classConfidence: 1)
            let memo = AlertCapture.memo(from: alert, receivedAt: received).map {
                Fixture.Memo(amountPaise: $0.amountPaise, direction: $0.direction.rawValue, payee: $0.payee,
                             vpa: $0.vpa, accountTail: $0.accountTail, dateISO: PendingMemo.istDayString($0.date),
                             captureHash: $0.captureHash)
            }
            XCTAssertEqual(memo, c.memo, "memo: \(c.name)")
            let row = AlertCapture.ledgerRow(from: alert, receivedAt: received).map {
                Fixture.Ledger(amountPaise: $0.amountPaise, direction: $0.direction.rawValue,
                               counterparty: $0.counterparty, reference: $0.reference ?? "",
                               narration: $0.narration, dateISO: PendingMemo.istDayString($0.date),
                               contentHash: $0.contentHash(source: .alert))
            }
            XCTAssertEqual(row, c.ledger, "ledger: \(c.name)")
        }
    }

    func testAlertSelfTransfersMatchFixture() throws {
        for c in try fixture().selfTransfers {
            var ids: [String: UUID] = [:]
            let rows = c.rows.map { r -> (id: UUID, reference: String, direction: Direction) in
                let id = UUID()
                ids[r[0]] = id
                return (id, r[1], Direction(rawValue: r[2])!)
            }
            let flagged = SelfTransfers.alerts(rows, bankSelfTransferRefs: Set(c.bankRefs))
            XCTAssertEqual(flagged, Set(c.expected.compactMap { ids[$0] }), c.name)
        }
    }

    func testAlertSourceIsPaymentAppSide() {
        XCTAssertEqual(Source.alert.kind, .paymentApp)
        XCTAssertEqual(Source.alert.displayName, "Captured alerts")
        XCTAssertFalse(Source.builtIn.contains(.alert))
    }
}
