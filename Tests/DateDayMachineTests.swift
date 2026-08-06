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

        let day = try repo.dayForRecord(in: m, at: t, now: t)

        XCTAssertEqual(day.dayIndex, 1)
        XCTAssertEqual(day.openedAt, t)
        XCTAssertNil(day.closedAt)
    }

    func testSecondRecordReusesOpenDay() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        let d1 = try repo.dayForRecord(in: m, at: Date(timeIntervalSince1970: 1_000),
                                       now: Date(timeIntervalSince1970: 1_000))
        let d2 = try repo.dayForRecord(in: m, at: Date(timeIntervalSince1970: 5_000),
                                       now: Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(d1.objectID, d2.objectID)
        XCTAssertEqual(try repo.daysSorted(in: m).count, 1)
    }

    func testSealThenNewRecordOpensNextDay() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        _ = try repo.dayForRecord(in: m, at: Date(timeIntervalSince1970: 1_000),
                                  now: Date(timeIntervalSince1970: 1_000))
        try repo.sealOpenDay(in: m, at: Date(timeIntervalSince1970: 40_000))

        let day2 = try repo.dayForRecord(in: m, at: Date(timeIntervalSince1970: 50_000),
                                         now: Date(timeIntervalSince1970: 50_000))

        XCTAssertEqual(day2.dayIndex, 2)
        let days = try repo.daysSorted(in: m)
        XCTAssertEqual(days.map(\.dayIndex), [1, 2])
        XCTAssertNotNil(days[0].closedAt)
        XCTAssertNil(days[1].closedAt)
    }

    // spec §5.1 修订 6：保险丝仅对「现记跨天」触发；补录与同日马拉松不拦
    func testStaleInterceptsOnlyLiveCrossDayRecords() throws {
        let cal = Calendar.current
        let (_, repo, m) = try makeOngoingMeeting()
        let opened = cal.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 20))!
        _ = try repo.dayForRecord(in: m, at: opened, now: opened)

        let nowOver = opened.addingTimeInterval(18 * 3600 + 60)    // 8/6 14:01，跨天且超时
        let nowUnder = opened.addingTimeInterval(18 * 3600 - 60)   // 8/6 13:59，跨天未超时

        XCTAssertNotNil(try repo.staleOpenDay(in: m, now: nowOver, recordAt: nowOver))
        XCTAssertNil(try repo.staleOpenDay(in: m, now: nowUnder, recordAt: nowUnder))
        // 补录过去日期：即便开着的天已超时也不拦
        let backfillAt = cal.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12))!
        XCTAssertNil(try repo.staleOpenDay(in: m, now: nowOver, recordAt: backfillAt))

        // 同日马拉松：开着的天与记录同一自然日，19 小时也不拦
        let (_, repo2, m2) = try makeOngoingMeeting()
        let sameDayOpened = cal.date(from: DateComponents(year: 2026, month: 8, day: 6, minute: 30))!
        _ = try repo2.dayForRecord(in: m2, at: sameDayOpened, now: sameDayOpened)
        let lateSameDay = sameDayOpened.addingTimeInterval(19 * 3600)
        XCTAssertNil(try repo2.staleOpenDay(in: m2, now: lateSameDay, recordAt: lateSameDay))
    }

    func testEndMeetingSealsOpenDay() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        _ = try repo.dayForRecord(in: m, at: Date(timeIntervalSince1970: 1_000),
                                  now: Date(timeIntervalSince1970: 1_000))

        let endTime = Date(timeIntervalSince1970: 90_000)
        try repo.end(m, at: endTime)

        XCTAssertNil(try repo.openDay(in: m))
        XCTAssertEqual(try repo.daysSorted(in: m).first?.closedAt, endTime)
    }
}
