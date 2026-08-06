import XCTest
@testable import Anniversary

/// 反馈③轮：补录归日区间规则（spec §5.1 修订 6）
final class DayAttributionTests: XCTestCase {
    private let cal = Calendar.current

    private func d(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 补录视角的"今天"：固定在 8/6 中午
    private var today: Date { d(8, 6, 12) }

    private func makeOngoingMeeting() throws -> (PersistenceController, MeetingRepository, CDMeeting) {
        let pc = PersistenceController(inMemory: true)
        let couple = try CoupleRepository(context: pc.viewContext)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: nil, city: "上海", plannedStart: nil, plannedEnd: nil)
        try repo.start(m, at: d(8, 1, 9))
        return (pc, repo, m)
    }

    // 跨午夜补录落进已封区间：8/1 天封在 8/2 02:47，补一条 8/2 01:30 → 归 8/1 的天
    func testBackfillLandsInSealedRangeAcrossMidnight() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        let day1 = try repo.dayForRecord(in: m, at: d(8, 1, 18), now: d(8, 1, 18))
        try repo.sealOpenDay(in: m, at: d(8, 2, 2, 47))

        let hit = try repo.dayForRecord(in: m, at: d(8, 2, 1, 30), now: today)

        XCTAssertEqual(hit.objectID, day1.objectID)          // 已封的天照收，补录不解封
        XCTAssertEqual(try repo.daysSorted(in: m).count, 1)
        XCTAssertEqual(day1.closedAt, d(8, 2, 2, 47))        // 封盘时刻不被动
    }

    // 区间外的过去日期 → 新开一天并自动以当日 23:59 收尾；同区间再补不再新开
    func testBackfillOutsideRangeCreatesAutoSealedDay() throws {
        let (_, repo, m) = try makeOngoingMeeting()

        let day = try repo.dayForRecord(in: m, at: d(8, 1, 15), now: today)

        XCTAssertEqual(day.openedAt, d(8, 1, 15))
        XCTAssertEqual(day.closedAt, d(8, 1, 23, 59))        // 区间默认上界占位
        let again = try repo.dayForRecord(in: m, at: d(8, 1, 20), now: today)
        XCTAssertEqual(again.objectID, day.objectID)
        XCTAssertEqual(try repo.daysSorted(in: m).count, 1)
    }

    // 乱序补录：先补 8/3 再补 8/1 → 天序按日期重排，第 1 天恒为最早
    func testOutOfOrderBackfillRenumbers() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        let d3 = try repo.dayForRecord(in: m, at: d(8, 3, 14), now: today)
        let d1 = try repo.dayForRecord(in: m, at: d(8, 1, 10), now: today)

        let days = try repo.daysSorted(in: m)
        XCTAssertEqual(days.map(\.dayIndex), [1, 2])
        XCTAssertEqual(days[0].objectID, d1.objectID)
        XCTAssertEqual(days[1].objectID, d3.objectID)
    }

    // 现记今天且区间外 → 新开的天保持未封（照旧手动封盘）
    func testTodayNewDayStaysOpen() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        let now = Date()
        let day = try repo.dayForRecord(in: m, at: now, now: now)
        XCTAssertNil(day.closedAt)
    }

    // 区间重叠时归 openedAt 最晚的命中天
    func testOverlapPicksLatestOpenedDay() throws {
        let (pc, repo, m) = try makeOngoingMeeting()
        _ = try repo.dayForRecord(in: m, at: d(8, 1, 12), now: today)   // [12:00, 23:59]
        let inner = CDDateDay(context: pc.viewContext)                   // 手工构造重叠窄区间
        inner.id = UUID()
        inner.openedAt = d(8, 1, 14)
        inner.closedAt = d(8, 1, 20)
        inner.meeting = m
        try pc.viewContext.save()

        let hit = try repo.dayForRecord(in: m, at: d(8, 1, 15), now: today)

        XCTAssertEqual(hit.objectID, inner.objectID)
    }

    // 编辑改期：自动按区间规则重归属，原天变空则清除并重排
    func testUpdateReattributesAndPrunesEmptyDay() throws {
        let (pc, repo, m) = try makeOngoingMeeting()
        _ = try repo.dayForRecord(in: m, at: d(8, 1, 10), now: today)    // 8/1 天 [10:00, 23:59]
        let momentRepo = MomentRepository(context: pc.viewContext)
        let moment = try momentRepo.create(in: m, type: .restaurant, title: "补录", body: nil,
                                           happenedAt: d(8, 2, 15), photoDatas: [],
                                           myEvaluation: nil, authorID: nil, place: nil)
        XCTAssertEqual(try repo.daysSorted(in: m).count, 2)              // 8/1 与 8/2 两天

        try momentRepo.update(moment, type: .restaurant, title: "补录", body: nil, happenedAt: d(8, 1, 16))

        XCTAssertEqual(moment.dateDay?.openedAt, d(8, 1, 10))            // 重归 8/1 的天
        let days = try repo.daysSorted(in: m)
        XCTAssertEqual(days.count, 1)                                    // 空的 8/2 天被清除
        XCTAssertEqual(days[0].dayIndex, 1)
    }
}
