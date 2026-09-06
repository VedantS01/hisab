import XCTest
@testable import HisabCore

final class MoneyTests: XCTestCase {
    func testZeroAndSubRupee() {
        XCTAssertEqual(Money.formatPaise(0), "₹0.00")
        XCTAssertEqual(Money.formatPaise(50), "₹0.50")
        XCTAssertEqual(Money.formatPaise(5), "₹0.05")
    }

    func testWesternRangeGrouping() {
        XCTAssertEqual(Money.formatPaise(123456), "₹1,234.56")
    }

    func testIndianGrouping() {
        XCTAssertEqual(Money.formatPaise(12345678), "₹1,23,456.78")
        XCTAssertEqual(Money.formatPaise(1234567890), "₹1,23,45,678.90")
    }

    func testNegative() {
        XCTAssertEqual(Money.formatPaise(-9900), "-₹99.00")
    }

    func testSignedPositive() {
        XCTAssertEqual(Money.formatPaise(9900, signed: true), "+₹99.00")
        XCTAssertEqual(Money.formatPaise(-9900, signed: true), "-₹99.00")
    }
}
