import XCTest
@testable import Anniversary

final class DateDayMachineTests: XCTestCase {
    private func makeOngoingMeeting() throws -> (PersistenceController, MeetingRepository, CDMeeting) {
        let pc = PersistenceController(inMemory: true)
        let couple = try CoupleRepository(context: pc.viewContext)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: nil, city: "上海", plannedStart: nil, plannedEnd: nil)
        try repo.start(m, at: Date(timeIntervalSince1970: 0))
        return (pc, repo, m)
    }

    func testFirstRecordOpensDayOne() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        let t = Date(timeIntervalSince1970: 1_000)

        let day = try repo.dayForNewRecord(in: m, at: t)

        XCTAssertEqual(day.dayIndex, 1)
        XCTAssertEqual(day.openedAt, t)
        XCTAssertNil(day.closedAt)
    }

    func testSecondRecordReusesOpenDay() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        let d1 = try repo.dayForNewRecord(in: m, at: Date(timeIntervalSince1970: 1_000))
        let d2 = try repo.dayForNewRecord(in: m, at: Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(d1.objectID, d2.objectID)
        XCTAssertEqual(try repo.daysSorted(in: m).count, 1)
    }

    func testSealThenNewRecordOpensNextDay() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        _ = try repo.dayForNewRecord(in: m, at: Date(timeIntervalSince1970: 1_000))
        try repo.sealOpenDay(in: m, at: Date(timeIntervalSince1970: 40_000))

        let day2 = try repo.dayForNewRecord(in: m, at: Date(timeIntervalSince1970: 50_000))

        XCTAssertEqual(day2.dayIndex, 2)
        let days = try repo.daysSorted(in: m)
        XCTAssertEqual(days.map(\.dayIndex), [1, 2])
        XCTAssertNotNil(days[0].closedAt)
        XCTAssertNil(days[1].closedAt)
    }

    func testStaleOpenDayAt18HourBoundary() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        let opened = Date(timeIntervalSince1970: 0)
        _ = try repo.dayForNewRecord(in: m, at: opened)

        let justUnder = opened.addingTimeInterval(18 * 3600 - 60)
        let justOver = opened.addingTimeInterval(18 * 3600 + 60)

        XCTAssertNil(try repo.staleOpenDay(in: m, now: justUnder))
        XCTAssertNotNil(try repo.staleOpenDay(in: m, now: justOver))
    }

    func testEndMeetingSealsOpenDay() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        _ = try repo.dayForNewRecord(in: m, at: Date(timeIntervalSince1970: 1_000))

        let endTime = Date(timeIntervalSince1970: 90_000)
        try repo.end(m, at: endTime)

        XCTAssertNil(try repo.openDay(in: m))
        XCTAssertEqual(try repo.daysSorted(in: m).first?.closedAt, endTime)
    }
}
