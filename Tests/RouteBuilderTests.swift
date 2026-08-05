import XCTest
@testable import Anniversary

final class RouteBuilderTests: XCTestCase {
    private func input(_ id: UUID, day: Int32, hour: Int, lat: Double = 31, lon: Double = 121) -> RouteStopInput {
        RouteStopInput(momentID: id, dayIndex: day,
                       happenedAt: Calendar.current.date(from: DateComponents(
                           year: 2026, month: 8, day: 15, hour: hour))!,
                       latitude: lat, longitude: lon)
    }

    func testGroupsByDayAndOrdersByTime() {
        let a = UUID(), b = UUID(), c = UUID()
        let days = RouteBuilder.days(from: [
            input(c, day: 2, hour: 20),
            input(a, day: 1, hour: 10),
            input(b, day: 1, hour: 14),
        ])
        XCTAssertEqual(days.map(\.dayIndex), [1, 2])
        XCTAssertEqual(days[0].stops.map(\.momentID), [a, b])
        XCTAssertEqual(days[0].stops.map(\.order), [1, 2])   // 每天序号从 1 重新起
        XCTAssertEqual(days[1].stops.map(\.order), [1])
    }

    func testEmptyInputsGiveEmptyDays() {
        XCTAssertTrue(RouteBuilder.days(from: []).isEmpty)
    }

    func testStopKeepsCoordinates() {
        let a = UUID()
        let days = RouteBuilder.days(from: [input(a, day: 1, hour: 9, lat: 31.2, lon: 121.5)])
        XCTAssertEqual(days[0].stops[0].latitude, 31.2)
        XCTAssertEqual(days[0].stops[0].longitude, 121.5)
    }
}
