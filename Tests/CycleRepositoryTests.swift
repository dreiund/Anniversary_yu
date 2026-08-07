import XCTest
import CoreData
@testable import Anniversary

final class CycleRepositoryTests: XCTestCase {
    private var pc: PersistenceController!
    private var couple: CDCouple!
    private var repo: CycleRepository!
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func d(_ day: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(day) * 86_400) }

    override func setUpWithError() throws {
        pc = PersistenceController(inMemory: true)
        couple = try CoupleRepository(context: pc.viewContext)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        repo = CycleRepository(context: pc.viewContext)
    }

    func testStartGuardsAndPersists() throws {
        let c = try repo.start(couple: couple, on: d(10), predictedStart: d(9), today: d(10), calendar: cal)
        XCTAssertEqual(c.startDate, cal.startOfDay(for: d(10)))
        XCTAssertNil(c.endDate)
        XCTAssertEqual(c.predictedStartAtLogging, d(9))
        XCTAssertNotNil(repo.ongoing(couple: couple))
        XCTAssertThrowsError(try repo.start(couple: couple, on: d(12), predictedStart: nil,
                                            today: d(12), calendar: cal)) {
            XCTAssertEqual($0 as? CycleRepository.CycleError, .hasOngoing)
        }
        try repo.end(c, on: d(14), calendar: cal)
        XCTAssertThrowsError(try repo.start(couple: couple, on: d(30), predictedStart: nil,
                                            today: d(20), calendar: cal)) {
            XCTAssertEqual($0 as? CycleRepository.CycleError, .future)
        }
    }

    func testEndValidatesOrder() throws {
        let c = try repo.start(couple: couple, on: d(10), predictedStart: nil, today: d(10), calendar: cal)
        XCTAssertThrowsError(try repo.end(c, on: d(9), calendar: cal)) {
            XCTAssertEqual($0 as? CycleRepository.CycleError, .endBeforeStart)
        }
        try repo.end(c, on: d(15), calendar: cal)
        XCTAssertEqual(c.endDate, cal.startOfDay(for: d(15)))
        XCTAssertNil(repo.ongoing(couple: couple))
    }

    func testBackfillOverlapRejected() throws {
        _ = try repo.backfill(couple: couple, start: d(10), end: d(15), today: d(50), calendar: cal)
        XCTAssertThrowsError(try repo.backfill(couple: couple, start: d(14), end: d(20),
                                               today: d(50), calendar: cal)) {
            guard case .overlap(let s, let e)? = $0 as? CycleRepository.CycleError else {
                return XCTFail("应为 overlap")
            }
            XCTAssertEqual(s, cal.startOfDay(for: d(10)))
            XCTAssertEqual(e, cal.startOfDay(for: d(15)))
        }
        // 与进行中段（上界开放）重叠同样拒绝
        _ = try repo.start(couple: couple, on: d(40), predictedStart: nil, today: d(40), calendar: cal)
        XCTAssertThrowsError(try repo.backfill(couple: couple, start: d(45), end: d(46),
                                               today: d(50), calendar: cal))
        // 不重叠的照常成功
        _ = try repo.backfill(couple: couple, start: d(20), end: d(24), today: d(50), calendar: cal)
        XCTAssertEqual(repo.cyclesSorted(couple: couple).count, 3)
        XCTAssertEqual(repo.cyclesSorted(couple: couple).first?.startDate, cal.startOfDay(for: d(40)))  // 降序
    }

    func testContainingAndUpdateRangeAndDeleteCascadesLogs() throws {
        let c = try repo.backfill(couple: couple, start: d(10), end: d(15), today: d(50), calendar: cal)
        XCTAssertNotNil(repo.cycle(containing: d(12), couple: couple, calendar: cal))
        XCTAssertNil(repo.cycle(containing: d(16), couple: couple, calendar: cal))
        try repo.updateRange(c, start: d(11), end: d(16), calendar: cal)
        XCTAssertEqual(c.startDate, cal.startOfDay(for: d(11)))
        _ = try repo.setDayLog(in: c, day: d(12), painRaw: 2, flowRaw: 3, colorRaw: 1,
                               note: "有点疼", calendar: cal)
        try repo.delete(c)
        let logs = try pc.viewContext.fetch(NSFetchRequest<CDCycleDayLog>(entityName: "CDCycleDayLog"))
        XCTAssertTrue(logs.isEmpty)                            // 模型级联
    }

    func testSetDayLogUpserts() throws {
        let c = try repo.start(couple: couple, on: d(10), predictedStart: nil, today: d(10), calendar: cal)
        _ = try repo.setDayLog(in: c, day: d(10), painRaw: 1, flowRaw: 2, colorRaw: 0, note: nil, calendar: cal)
        let updated = try repo.setDayLog(in: c, day: d(10), painRaw: 3, flowRaw: 2, colorRaw: 2,
                                         note: "改了", calendar: cal)
        XCTAssertEqual(updated.painRaw, 3)
        let logs = try pc.viewContext.fetch(NSFetchRequest<CDCycleDayLog>(entityName: "CDCycleDayLog"))
        XCTAssertEqual(logs.count, 1)                          // 同一天只有一条
        XCTAssertEqual(repo.dayLog(in: c, day: d(10), calendar: cal)?.note, "改了")
    }

    func testAddIntimacyTimeAndMeetingAttachment() throws {
        // 今天 + 见面进行中 → happenedAt=now、挂开着的约会日；过去天 → 当天 12:00、不挂
        let meetings = MeetingRepository(context: pc.viewContext)
        let m = try meetings.createPlanned(couple: couple, title: nil, city: nil,
                                           plannedStart: nil, plannedEnd: nil)
        try meetings.start(m, at: d(10))
        let now = d(10).addingTimeInterval(80_000)
        _ = try meetings.dayForRecord(in: m, at: d(10).addingTimeInterval(3_600), now: now, calendar: cal)
        let today = try repo.addIntimacy(couple: couple, day: d(10), protected: true,
                                         note: nil, now: now, calendar: cal)
        XCTAssertEqual(today.happenedAt, now)
        XCTAssertNotNil(today.dateDay)
        XCTAssertEqual(today.protectionUsed, true)
        let past = try repo.addIntimacy(couple: couple, day: d(5), protected: false,
                                        note: "补", now: now, calendar: cal)
        XCTAssertEqual(past.happenedAt, cal.date(bySettingHour: 12, minute: 0, second: 0, of: d(5)))
        XCTAssertNil(past.dateDay)
        XCTAssertEqual(repo.intimacy(on: d(5), couple: couple, calendar: cal).count, 1)
        try repo.updateIntimacy(past, protected: true, note: "改")
        XCTAssertEqual(past.protectionUsed, true)
        try repo.deleteIntimacy(past)
        XCTAssertTrue(repo.intimacy(on: d(5), couple: couple, calendar: cal).isEmpty)
    }

    /// I1：backfill 的结束日、updateRange 的起止都不能落在未来（今天显式传参，固定日期）
    func testBackfillAndUpdateRangeRejectFutureDates() throws {
        XCTAssertThrowsError(try repo.backfill(couple: couple, start: d(10), end: d(60),
                                               today: d(50), calendar: cal)) {
            XCTAssertEqual($0 as? CycleRepository.CycleError, .future)
        }
        let c = try repo.backfill(couple: couple, start: d(10), end: d(15), today: d(50), calendar: cal)
        XCTAssertThrowsError(try repo.updateRange(c, start: d(11), end: d(60),
                                                   today: d(50), calendar: cal)) {
            XCTAssertEqual($0 as? CycleRepository.CycleError, .future)
        }
        XCTAssertThrowsError(try repo.updateRange(c, start: d(60), end: d(65),
                                                   today: d(50), calendar: cal)) {
            XCTAssertEqual($0 as? CycleRepository.CycleError, .future)
        }
        // 未越界的照常成功
        try repo.updateRange(c, start: d(11), end: d(16), today: d(50), calendar: cal)
        XCTAssertEqual(c.startDate, cal.startOfDay(for: d(11)))
        XCTAssertEqual(c.endDate, cal.startOfDay(for: d(16)))
    }

    func testTrackedPartnerExclusive() throws {
        let partners = CoupleRepository(context: pc.viewContext).partners(of: couple)
        XCTAssertNil(repo.trackedPartner(couple: couple))
        try repo.setTracked(partners[0], couple: couple)
        XCTAssertEqual(repo.trackedPartner(couple: couple)?.objectID, partners[0].objectID)
        try repo.setTracked(partners[1], couple: couple)      // 独占：换人旧的置 false
        XCTAssertEqual(repo.trackedPartner(couple: couple)?.objectID, partners[1].objectID)
        XCTAssertFalse(partners[0].tracksCycle)
    }
}
