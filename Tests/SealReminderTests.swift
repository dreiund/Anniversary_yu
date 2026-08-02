import XCTest
@testable import Anniversary

final class SealReminderTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ h: Int, _ m: Int) -> Date {
        calendar.date(bySettingHour: h, minute: m, second: 0, of: Date())!
    }

    func testOpenDayBeforeHalfPastElevenSchedulesToday() {
        let now = date(21, 0)
        let decision = SealReminderPlanner.decision(hasOpenDay: true, enabled: true, now: now, calendar: calendar)
        XCTAssertEqual(decision, .schedule(date(23, 30)))
    }

    func testOpenDayAfterHalfPastElevenSchedulesTomorrow() {
        let now = date(23, 45)
        let expected = calendar.date(byAdding: .day, value: 1, to: date(23, 30))!
        XCTAssertEqual(SealReminderPlanner.decision(hasOpenDay: true, enabled: true, now: now, calendar: calendar),
                       .schedule(expected))
    }

    func testExactlyHalfPastElevenSchedulesTomorrow() {
        let now = date(23, 30)
        let expected = calendar.date(byAdding: .day, value: 1, to: date(23, 30))!
        XCTAssertEqual(SealReminderPlanner.decision(hasOpenDay: true, enabled: true, now: now, calendar: calendar),
                       .schedule(expected))
    }

    func testNoOpenDayCancels() {
        XCTAssertEqual(SealReminderPlanner.decision(hasOpenDay: false, enabled: true, now: date(21, 0), calendar: calendar),
                       .cancel)
    }

    func testDisabledCancelsEvenWithOpenDay() {
        XCTAssertEqual(SealReminderPlanner.decision(hasOpenDay: true, enabled: false, now: date(21, 0), calendar: calendar),
                       .cancel)
    }
}
