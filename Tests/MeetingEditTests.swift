import XCTest
import CoreData
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

    func testUpdateOngoingWritesStartedAtAndPlannedEnd() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil,
                                       plannedStart: Date(timeIntervalSince1970: 100), plannedEnd: nil)
        try repo.start(m, at: Date(timeIntervalSince1970: 500))
        try repo.update(m, title: "改题", city: "杭州",
                        start: Date(timeIntervalSince1970: 600),
                        end: Date(timeIntervalSince1970: 700))
        XCTAssertEqual(m.startedAt, Date(timeIntervalSince1970: 600))
        XCTAssertNil(m.endedAt)                                    // ongoing 不写实际结束
        XCTAssertEqual(m.plannedEnd, Date(timeIntervalSince1970: 700))    // 反馈：行程延后，预计结束可改
        XCTAssertEqual(m.plannedStart, Date(timeIntervalSince1970: 100))  // 计划开始不动
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

    // 反馈：足迹列表左滑删除——任意状态可删（含级联与重编号），开发期清理瞎建数据
    func testDeleteAnyStatusCascadesAndRenumbers() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let moments = MomentRepository(context: pc.viewContext)
        let m1 = try repo.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        try repo.start(m1, at: Date(timeIntervalSince1970: 100))
        _ = try moments.create(in: m1, type: .other, title: "留下", body: nil,
                               happenedAt: Date(timeIntervalSince1970: 150), photoDatas: [],
                               myEvaluation: nil, authorID: nil, place: nil)
        try repo.end(m1, at: Date(timeIntervalSince1970: 200))
        let m2 = try repo.createPlanned(couple: couple, title: "要删", city: nil, plannedStart: nil, plannedEnd: nil)
        try repo.start(m2, at: Date(timeIntervalSince1970: 300))
        _ = try moments.create(in: m2, type: .other, title: "陪葬", body: nil,
                               happenedAt: Date(timeIntervalSince1970: 350), photoDatas: [],
                               myEvaluation: nil, authorID: nil, place: nil)
        try repo.end(m2, at: Date(timeIntervalSince1970: 400))
        let m3 = try repo.createPlanned(couple: couple, title: "殿后", city: nil, plannedStart: nil, plannedEnd: nil)

        try repo.delete(m2)                                        // 已结束的也能删

        XCTAssertEqual(try repo.meetingsSorted(couple: couple).count, 2)
        XCTAssertEqual(m1.index, 1)
        XCTAssertEqual(m3.index, 2)                                // 序号前移保持连续
        let leftMoments = try pc.viewContext.fetch(NSFetchRequest<CDMoment>(entityName: "CDMoment"))
        XCTAssertEqual(leftMoments.compactMap(\.title), ["留下"])   // m2 的记忆级联删除，m1 的保留
        let leftDays = try pc.viewContext.fetch(NSFetchRequest<CDDateDay>(entityName: "CDDateDay"))
        XCTAssertEqual(leftDays.count, 1)                          // 只剩 m1 的约会日
    }

    // 反馈：封盘天可删——仅空天；还有记忆时拒绝，删后天序号前移
    func testDeleteDayOnlyWhenEmptyAndRenumbers() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        try repo.start(m, at: Date(timeIntervalSince1970: 0))
        func day(_ idx: Int32, opened: TimeInterval, closed: TimeInterval) -> CDDateDay {
            let d = CDDateDay(context: pc.viewContext)
            d.id = UUID(); d.dayIndex = idx
            d.openedAt = Date(timeIntervalSince1970: opened)
            d.closedAt = Date(timeIntervalSince1970: closed)
            d.meeting = m
            return d
        }
        let d1 = day(1, opened: 100, closed: 200)
        let mo = CDMoment(context: pc.viewContext)
        mo.id = UUID(); mo.title = "占着"; mo.happenedAt = Date(timeIntervalSince1970: 150)
        mo.dateDay = d1
        let d2 = day(2, opened: 86_500, closed: 86_600)          // 删光记忆后遗留的空封盘天
        let d3 = day(3, opened: 172_900, closed: 173_000)
        try pc.viewContext.save()

        XCTAssertThrowsError(try repo.deleteDay(d1))             // 还有记忆：拒绝
        try repo.deleteDay(d2)                                   // 空天可删
        XCTAssertEqual(try repo.daysSorted(in: m).map(\.dayIndex), [1, 2])
        XCTAssertEqual(d3.dayIndex, 2)                           // 序号前移
    }

    // 反馈：批量管理——见面多选删除后序号保持连续
    func testDeleteMeetingsBatchRenumbers() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m1 = try repo.createPlanned(couple: couple, title: "留", city: nil, plannedStart: nil, plannedEnd: nil)
        let m2 = try repo.createPlanned(couple: couple, title: "删A", city: nil, plannedStart: nil, plannedEnd: nil)
        let m3 = try repo.createPlanned(couple: couple, title: "留", city: nil, plannedStart: nil, plannedEnd: nil)
        let m4 = try repo.createPlanned(couple: couple, title: "删B", city: nil, plannedStart: nil, plannedEnd: nil)
        try repo.delete([m2, m4])
        XCTAssertEqual(try repo.meetingsSorted(couple: couple).count, 2)
        XCTAssertEqual(m1.index, 1)
        XCTAssertEqual(m3.index, 2)
    }

    // 反馈：批量管理——记忆与行前日程的多选删除
    func testDeleteMomentsAndPlanItemsBatch() throws {
        let (pc, couple) = try makeCouple()
        let meetings = MeetingRepository(context: pc.viewContext)
        let moments = MomentRepository(context: pc.viewContext)
        let m = try meetings.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        try meetings.start(m, at: Date(timeIntervalSince1970: 100))
        let a = try moments.create(in: m, type: .other, title: "A", body: nil,
                                   happenedAt: Date(timeIntervalSince1970: 150), photoDatas: [],
                                   myEvaluation: nil, authorID: nil, place: nil)
        _ = try moments.create(in: m, type: .other, title: "B", body: nil,
                               happenedAt: Date(timeIntervalSince1970: 160), photoDatas: [],
                               myEvaluation: nil, authorID: nil, place: nil)
        let c = try moments.create(in: m, type: .other, title: "C", body: nil,
                                   happenedAt: Date(timeIntervalSince1970: 170), photoDatas: [],
                                   myEvaluation: nil, authorID: nil, place: nil)
        try moments.delete([a, c])
        let left = try pc.viewContext.fetch(NSFetchRequest<CDMoment>(entityName: "CDMoment"))
        XCTAssertEqual(left.compactMap(\.title), ["B"])

        let plans = PlanItemRepository(context: pc.viewContext)
        let p1 = try plans.add(to: m, day: nil, time: nil, title: "P1", note: nil, placeText: nil, authorID: nil)
        let p2 = try plans.add(to: m, day: nil, time: nil, title: "P2", note: nil, placeText: nil, authorID: nil)
        try plans.delete([p1, p2])
        XCTAssertTrue(try pc.viewContext.fetch(CDPlanItem.fetchRequest()).isEmpty)
    }

    func testDeleteNonPlannedThrows() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        try repo.start(m, at: Date(timeIntervalSince1970: 100))
        XCTAssertThrowsError(try repo.deletePlanned(m))
    }

    func testPlanItemRemindAtPersists() throws {
        let (pc, couple) = try makeCouple()
        let meetings = MeetingRepository(context: pc.viewContext)
        let m = try meetings.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        let plans = PlanItemRepository(context: pc.viewContext)
        let item = try plans.add(to: m, day: nil, time: nil, title: "买票", note: nil,
                                 placeText: nil, authorID: nil, remindAt: Date(timeIntervalSince1970: 500))
        XCTAssertEqual(item.remindAt, Date(timeIntervalSince1970: 500))
        try plans.update(item, day: nil, time: nil, title: "买票", note: nil, placeText: nil,
                         remindAt: nil, place: nil)
        XCTAssertNil(item.remindAt)
    }
}
