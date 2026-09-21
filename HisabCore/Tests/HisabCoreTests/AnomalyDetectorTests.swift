import XCTest
@testable import HisabCore

final class AnomalyDetectorTests: XCTestCase {
    private let config = InsightsConfig.fallback

    private func stamp(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = iso.count > 10 ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func record(_ id: String, _ iso: String, _ paise: Int64,
                        _ merchant: String) -> InsightRecord {
        InsightRecord(id: id, date: stamp(iso), amountPaise: paise, direction: .debit,
                      category: "Food", merchant: merchant)
    }

    private let now = "2026-09-15"

    func testSameDayIdenticalPaymentsAreAPossibleDuplicate() {
        let records = [record("a", "2026-09-10", 45_000, "Swiggy"),
                       record("b", "2026-09-10", 45_000, "Swiggy")]
        let insights = AnomalyDetector.detect(records: records, now: stamp(now),
                                              monthDebitTotalPaise: 90_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].kind, .possibleDuplicate)
        XCTAssertEqual(insights[0].headline, "Swiggy: ₹450.00 ×2")
        XCTAssertEqual(insights[0].detail, "2 identical payments on 10 Sep 2026")
        XCTAssertEqual(insights[0].evidenceIDs, ["a", "b"])
        XCTAssertEqual(insights[0].mute, .merchant("swiggy"))
    }

    func testDifferentMerchantsSameAmountAreNotDuplicates() {
        let records = [record("a", "2026-09-10", 45_000, "Swiggy"),
                       record("b", "2026-09-10", 45_000, "Zomato")]
        XCTAssertTrue(AnomalyDetector.detect(records: records, now: stamp(now),
                                             monthDebitTotalPaise: 90_000,
                                             config: config).isEmpty)
    }

    func testTimestampedPaymentsHoursApartAreNotDuplicates() {
        let records = [record("a", "2026-09-10 09:15", 45_000, "Swiggy"),
                       record("b", "2026-09-10 20:40", 45_000, "Swiggy")]
        XCTAssertTrue(AnomalyDetector.detect(records: records, now: stamp(now),
                                             monthDebitTotalPaise: 90_000,
                                             config: config).isEmpty)
    }

    func testTimestampedPaymentsWithinTheWindowAreDuplicates() {
        let records = [record("a", "2026-09-10 09:15", 45_000, "Swiggy"),
                       record("b", "2026-09-10 09:19", 45_000, "Swiggy")]
        let insights = AnomalyDetector.detect(records: records, now: stamp(now),
                                              monthDebitTotalPaise: 90_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].kind, .possibleDuplicate)
    }

    func testAnAmountFarAboveTheMerchantMedianIsAnOutlier() {
        var records = (1...5).map { index in
            record("p\(index)", "2026-08-0\(index)", 30_000, "Blue Tokai")
        }
        records.append(record("big", "2026-09-10", 250_000, "Blue Tokai"))
        let insights = AnomalyDetector.detect(records: records, now: stamp(now),
                                              monthDebitTotalPaise: 400_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].kind, .outlierAmount)
        XCTAssertEqual(insights[0].headline, "Blue Tokai: ₹2,500.00")
        XCTAssertEqual(insights[0].detail, "about 8× your usual ₹300.00")
        XCTAssertEqual(insights[0].evidenceIDs, ["big"])
    }

    func testTooFewPriorsMeansNoOutlier() {
        var records = (1...4).map { index in
            record("p\(index)", "2026-08-0\(index)", 30_000, "Blue Tokai")
        }
        records.append(record("big", "2026-09-10", 250_000, "Blue Tokai"))
        XCTAssertTrue(AnomalyDetector.detect(records: records, now: stamp(now),
                                             monthDebitTotalPaise: 400_000,
                                             config: config).isEmpty)
    }

    func testASmallMultipleBelowTheRupeeFloorIsNotAnOutlier() {
        var records = (1...5).map { index in
            record("p\(index)", "2026-08-0\(index)", 10_000, "Chaiwala")
        }
        records.append(record("big", "2026-09-10", 40_000, "Chaiwala"))
        XCTAssertTrue(AnomalyDetector.detect(records: records, now: stamp(now),
                                             monthDebitTotalPaise: 90_000,
                                             config: config).isEmpty)
    }

    func testAnythingOlderThanTheLookbackIsIgnored() {
        let records = [record("a", "2026-06-10", 45_000, "Swiggy"),
                       record("b", "2026-06-10", 45_000, "Swiggy")]
        XCTAssertTrue(AnomalyDetector.detect(records: records, now: stamp(now),
                                             monthDebitTotalPaise: 90_000,
                                             config: config).isEmpty)
    }
}
