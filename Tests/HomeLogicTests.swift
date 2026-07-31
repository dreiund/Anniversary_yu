import XCTest
@testable import Anniversary

final class HomeLogicTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    func testDaysTogetherInclusive() {
        let anniversary = date(2025, 6, 9)
        XCTAssertEqual(HomeLogic.daysTogether(anniversary: anniversary, today: date(2025, 6, 9), calendar: cal), 1)
        XCTAssertEqual(HomeLogic.daysTogether(anniversary: anniversary, today: date(2025, 6, 10), calendar: cal), 2)
        XCTAssertEqual(HomeLogic.daysTogether(anniversary: anniversary, today: date(2026, 7, 25), calendar: cal), 412)
    }

    func testCountdownDays() {
        XCTAssertEqual(HomeLogic.countdownDays(to: date(2026, 8, 29), from: date(2026, 8, 17), calendar: cal), 12)
        XCTAssertEqual(HomeLogic.countdownDays(to: date(2026, 8, 29), from: date(2026, 8, 29, 23), calendar: cal), 0)
        XCTAssertEqual(HomeLogic.countdownDays(to: date(2026, 8, 29), from: date(2026, 9, 1), calendar: cal), 0)
    }

    func testDaysToNextAnniversary() {
        let anniversary = date(2025, 6, 9)
        XCTAssertEqual(HomeLogic.daysToNextAnniversary(anniversary: anniversary, today: date(2026, 6, 1), calendar: cal), 8)
        XCTAssertEqual(HomeLogic.daysToNextAnniversary(anniversary: anniversary, today: date(2026, 6, 9), calendar: cal), 0)
        XCTAssertEqual(HomeLogic.daysToNextAnniversary(anniversary: anniversary, today: date(2026, 6, 10), calendar: cal), 364)
    }

    func testFeb29AnniversaryFallsBackToFeb28InNonLeapYears() {
        let anniversary = date(2024, 2, 29)
        XCTAssertEqual(HomeLogic.daysToNextAnniversary(anniversary: anniversary, today: date(2025, 2, 27), calendar: cal), 1)
        XCTAssertEqual(HomeLogic.daysToNextAnniversary(anniversary: anniversary, today: date(2025, 2, 28), calendar: cal), 0)
        XCTAssertEqual(HomeLogic.daysToNextAnniversary(anniversary: anniversary, today: date(2025, 3, 1), calendar: cal), 364)
        XCTAssertEqual(HomeLogic.daysToNextAnniversary(anniversary: anniversary, today: date(2028, 2, 29), calendar: cal), 0)
    }
}
