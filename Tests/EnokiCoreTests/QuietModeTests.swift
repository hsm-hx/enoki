import XCTest
@testable import EnokiCore

final class QuietModeTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 2) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    func testNormalAndOff() {
        XCTAssertFalse(QuietMode.normal.isQuiet(at: date(10), calendar: calendar))
        XCTAssertTrue(QuietMode.off.isQuiet(at: date(10), calendar: calendar))
        XCTAssertNil(QuietMode.off.expiry)
        XCTAssertFalse(QuietMode.off.isExpired(at: date(23)))
    }

    func testUntilBoundary() {
        let mode = QuietMode.until(date(11))
        XCTAssertTrue(mode.isQuiet(at: date(10, 59), calendar: calendar))
        XCTAssertFalse(mode.isQuiet(at: date(11), calendar: calendar))   // 境界は「もう静かでない」
        XCTAssertFalse(mode.isExpired(at: date(10, 59)))
        XCTAssertTrue(mode.isExpired(at: date(11)))
    }

    func testEndOfWorkDayBeforeWorkEnd() {
        let mode = QuietMode.endOfWorkDay(from: date(10), workEndHour: 18, calendar: calendar)
        XCTAssertEqual(mode.expiry, date(18))
        XCTAssertTrue(mode.isQuiet(at: date(17, 59), calendar: calendar))
        XCTAssertFalse(mode.isQuiet(at: date(18), calendar: calendar))
    }

    func testEndOfWorkDayAfterWorkEndUsesMidnight() {
        let mode = QuietMode.endOfWorkDay(from: date(20), workEndHour: 18, calendar: calendar)
        XCTAssertEqual(mode.expiry, date(0, 0, day: 3))
        XCTAssertTrue(mode.isQuiet(at: date(23, 59), calendar: calendar))
        XCTAssertFalse(mode.isQuiet(at: date(0, 0, day: 3), calendar: calendar))
    }

    func testPersistenceRoundTrip() {
        let now = date(10)
        let until = QuietMode.until(date(11))
        XCTAssertEqual(until.rawValue, "until")
        XCTAssertEqual(QuietMode(rawValue: until.rawValue, until: until.expiry, now: now), until)

        let workday = QuietMode.endOfWorkDay(from: now, workEndHour: 18, calendar: calendar)
        XCTAssertEqual(workday.rawValue, "untilEndOfWorkDay")
        XCTAssertEqual(QuietMode(rawValue: workday.rawValue, until: workday.expiry, now: now), workday)

        // 期限切れは normal に落とす
        XCTAssertEqual(QuietMode(rawValue: "until", until: date(11), now: date(12)), .normal)
        XCTAssertEqual(QuietMode(rawValue: "until", until: nil, now: now), .normal)
        XCTAssertEqual(QuietMode(rawValue: nil, until: nil, now: now), .normal)
        XCTAssertEqual(QuietMode(rawValue: "off", until: nil, now: now), .off)
    }
}
