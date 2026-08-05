import XCTest
@testable import Anniversary

final class MeetingEditTests: XCTestCase {
    private func makeCouple() throws -> (PersistenceController, CDCouple) {
        let pc = PersistenceController(inMemory: true)
        let couple = try CoupleRepository(context: pc.viewContext)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        return (pc, couple)
    }

    func testUpdatePlannedWritesPlannedDates() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: "旧", city: "上海",
                                       plannedStart: Date(timeIntervalSince1970: 100),
                                       plannedEnd: Date(timeIntervalSince1970: 200))
        try repo.update(m, title: "新", city: nil,
                        start: Date(timeIntervalSince1970: 300),
                        end: Date(timeIntervalSince1970: 400))
        XCTAssertEqual(m.title, "新")
        XCTAssertNil(m.city)
        XCTAssertEqual(m.plannedStart, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(m.plannedEnd, Date(timeIntervalSince1970: 400))
        XCTAssertNil(m.startedAt)
    }

    func testUpdateOngoingWritesStartedAtOnly() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil,
                                       plannedStart: Date(timeIntervalSince1970: 100), plannedEnd: nil)
        try repo.start(m, at: Date(timeIntervalSince1970: 500))
        try repo.update(m, title: "改题", city: "杭州",
                        start: Date(timeIntervalSince1970: 600),
                        end: Date(timeIntervalSince1970: 700))
        XCTAssertEqual(m.startedAt, Date(timeIntervalSince1970: 600))
        XCTAssertNil(m.endedAt)                                    // ongoing 不写结束
        XCTAssertEqual(m.plannedStart, Date(timeIntervalSince1970: 100))  // 计划日期不动
    }

    func testUpdateFinishedWritesStartedAndEnded() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil,
                                       plannedStart: nil, plannedEnd: nil)
        try repo.start(m, at: Date(timeIntervalSince1970: 500))
        try repo.end(m, at: Date(timeIntervalSince1970: 900))
        try repo.update(m, title: nil, city: nil,
                        start: Date(timeIntervalSince1970: 550),
                        end: Date(timeIntervalSince1970: 950))
        XCTAssertEqual(m.startedAt, Date(timeIntervalSince1970: 550))
        XCTAssertEqual(m.endedAt, Date(timeIntervalSince1970: 950))
    }

    func testDeletePlannedCascadesItemsAndRenumbers() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m1 = try repo.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        try repo.start(m1, at: Date(timeIntervalSince1970: 100))
        try repo.end(m1, at: Date(timeIntervalSince1970: 200))     // idx1 已结束
        let m2 = try repo.createPlanned(couple: couple, title: "要删", city: nil, plannedStart: nil, plannedEnd: nil)
        let item = CDPlanItem(context: pc.viewContext)
        item.id = UUID(); item.title = "买票"; item.meeting = m2
        let m3 = try repo.createPlanned(couple: couple, title: "殿后", city: nil, plannedStart: nil, plannedEnd: nil)
        try pc.viewContext.save()

        try repo.deletePlanned(m2)

        let meetings = try repo.meetingsSorted(couple: couple)
        XCTAssertEqual(meetings.count, 2)
        XCTAssertEqual(m1.index, 1)
        XCTAssertEqual(m3.index, 2)                                // 不论状态整体前移
        let items = try pc.viewContext.fetch(CDPlanItem.fetchRequest())
        XCTAssertTrue(items.isEmpty)                               // 日程级联删除
    }

    func testDeleteNonPlannedThrows() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        try repo.start(m, at: Date(timeIntervalSince1970: 100))
        XCTAssertThrowsError(try repo.deletePlanned(m))
    }
}
