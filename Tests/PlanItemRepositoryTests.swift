import XCTest
import CoreData
@testable import Anniversary

final class PlanItemRepositoryTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: PlanItemRepository!
    private var meeting: CDMeeting!
    private let cal = Calendar(identifier: .gregorian)

    override func setUpWithError() throws {
        pc = PersistenceController(inMemory: true)
        let couple = try CoupleRepository(context: pc.viewContext)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        meeting = try MeetingRepository(context: pc.viewContext)
            .createPlanned(couple: couple, title: nil, city: "上海", plannedStart: nil, plannedEnd: nil)
        repo = PlanItemRepository(context: pc.viewContext)
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testSectionsSortRule() throws {
        // 规则：日期升序 → 同日内全天(无时间)在前、有时间按时间升序、再按 sortIndex → 无日期归备忘区按 sortIndex
        _ = try repo.add(to: meeting, day: date(2026, 8, 30), time: date(2026, 8, 30, 19, 30),
                         title: "辉哥火锅", note: nil, placeText: nil, authorID: nil)
        _ = try repo.add(to: meeting, day: date(2026, 8, 30), time: nil,
                         title: "迪士尼", note: nil, placeText: nil, authorID: nil)
        _ = try repo.add(to: meeting, day: date(2026, 8, 29), time: date(2026, 8, 29, 14, 0),
                         title: "高铁", note: nil, placeText: nil, authorID: nil)
        _ = try repo.add(to: meeting, day: nil, time: nil,
                         title: "带充电宝", note: nil, placeText: nil, authorID: nil)
        _ = try repo.add(to: meeting, day: nil, time: nil,
                         title: "晕车药", note: nil, placeText: nil, authorID: nil)

        let s = repo.sections(for: meeting, calendar: cal)

        XCTAssertEqual(s.dated.count, 2)
        XCTAssertEqual(s.dated[0].items.map(\.title), ["高铁"])
        XCTAssertEqual(s.dated[1].items.map(\.title), ["迪士尼", "辉哥火锅"])
        XCTAssertEqual(s.undated.map(\.title), ["带充电宝", "晕车药"])
    }

    func testToggleAndStats() throws {
        let a = try repo.add(to: meeting, day: nil, time: nil, title: "订酒店", note: nil, placeText: nil, authorID: nil)
        _ = try repo.add(to: meeting, day: nil, time: nil, title: "订车票", note: nil, placeText: nil, authorID: nil)

        try repo.toggleDone(a)
        var st = repo.stats(for: meeting)
        XCTAssertEqual(st.planned, 2)
        XCTAssertEqual(st.done, 1)

        try repo.toggleDone(a)
        st = repo.stats(for: meeting)
        XCTAssertEqual(st.done, 0)
    }

    func testUpdateAndDelete() throws {
        let a = try repo.add(to: meeting, day: nil, time: nil, title: "旧", note: nil, placeText: nil, authorID: nil)
        try repo.update(a, day: date(2026, 8, 29), time: nil, title: "新", note: "备注", placeText: "湖滨路店", remindAt: nil, place: nil)
        XCTAssertEqual(a.title, "新")
        XCTAssertEqual(repo.sections(for: meeting, calendar: cal).dated.count, 1)

        try repo.delete(a)
        XCTAssertEqual(repo.stats(for: meeting).planned, 0)
    }

    func testSectionsSortRuleLocksTimeAndTieBreak() throws {
        // 第3层锁定：时间升序（故意先add晚的再add早的，验证排序不依赖add顺序）
        let item1 = try repo.add(to: meeting, day: date(2026, 9, 1), time: date(2026, 9, 1, 19, 30),
                                  title: "火锅", note: nil, placeText: nil, authorID: nil)
        let item2 = try repo.add(to: meeting, day: date(2026, 9, 1), time: date(2026, 9, 1, 9, 0),
                                  title: "早茶", note: nil, placeText: nil, authorID: nil)

        // 第4层锁定：全天条目的 sortIndex tie-break
        let item3 = try repo.add(to: meeting, day: date(2026, 9, 2), time: nil,
                                  title: "A全天", note: nil, placeText: nil, authorID: nil)
        let item4 = try repo.add(to: meeting, day: date(2026, 9, 2), time: nil,
                                  title: "B全天", note: nil, placeText: nil, authorID: nil)

        // sortIndex 赋值验证：第一条 add 的 item.sortIndex == 0，后续递增
        XCTAssertEqual(item1.sortIndex, 0)
        XCTAssertEqual(item2.sortIndex, 1)
        XCTAssertEqual(item3.sortIndex, 2)
        XCTAssertEqual(item4.sortIndex, 3)

        let s = repo.sections(for: meeting, calendar: cal)

        // 验证第3层：时间升序
        XCTAssertEqual(s.dated[0].items.map(\.title), ["早茶", "火锅"])

        // 验证第4层：全天条目按 sortIndex 排序
        XCTAssertEqual(s.dated[1].items.map(\.title), ["A全天", "B全天"])
    }

    func testSectionsSortIgnoresTimeCalendarDate() throws {
        // 反馈⑩bug1 回归:旧数据(反馈⑧前)time 的年月日是「保存当天」——
        // 8/1 保存的 15:50(Date=8/1 15:50)与 8/5 保存的 09:00(Date=8/5 09:00)同排 8/20 的日程,
        // 直接比完整 Date 会把 09:00 排到 15:50 后面;修复后只比时分
        _ = try repo.add(to: meeting, day: date(2026, 8, 20), time: date(2026, 8, 1, 15, 50),
                         title: "起飞", note: nil, placeText: nil, authorID: nil)
        _ = try repo.add(to: meeting, day: date(2026, 8, 20), time: date(2026, 8, 5, 9, 0),
                         title: "早餐", note: nil, placeText: nil, authorID: nil)
        let s = repo.sections(for: meeting, calendar: cal)
        XCTAssertEqual(s.dated[0].items.map(\.title), ["早餐", "起飞"])
    }

    func testAddDefaultsToSharedAndExplicitPrivate() throws {
        let a = try repo.add(to: meeting, day: Date(), time: nil, title: "公开项",
                             note: nil, placeText: nil, authorID: nil)
        XCTAssertEqual(a.visibilityRaw, EntryVisibility.sharedImmediately.rawValue)
        let b = try repo.add(to: meeting, day: Date(), time: nil, title: "私密项",
                             note: nil, placeText: nil, authorID: nil,
                             visibility: .privateUntilRevealed)
        XCTAssertEqual(b.visibilityRaw, EntryVisibility.privateUntilRevealed.rawValue)
        XCTAssertNil(b.revealedAt)
    }

    func testRevealIsIdempotent() throws {
        let item = try repo.add(to: meeting, day: Date(), time: nil, title: "x",
                                note: nil, placeText: nil, authorID: nil,
                                visibility: .privateUntilRevealed)
        let t1 = Date(timeIntervalSince1970: 100)
        try repo.reveal(item, at: t1)
        XCTAssertEqual(item.revealedAt, t1)
        try repo.reveal(item, at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(item.revealedAt, t1)   // 时戳留痕,不可覆盖
    }

    func testEvidenceAddSortDeleteCascade() throws {
        let item = try repo.add(to: meeting, day: Date(), time: nil, title: "带照片",
                                note: nil, placeText: nil, authorID: nil)
        try repo.addEvidences(item, datas: [Data([0x1]), Data([0x2])])
        try repo.addEvidences(item, datas: [Data([0x3])])
        XCTAssertEqual(repo.evidencesSorted(item).map(\.sortIndex), [0, 1, 2])
        try repo.deleteEvidence(repo.evidencesSorted(item)[1])
        XCTAssertEqual(repo.evidencesSorted(item).count, 2)
        try repo.delete(item)
        let fetch = NSFetchRequest<CDEvidence>(entityName: "CDEvidence")
        XCTAssertEqual((try pc.viewContext.fetch(fetch)).count, 0)   // 删父级联删照片
    }

    /// 统计按观看者可见口径(spec §三.5):nil=全量;私密未公开只计作者侧
    func testStatsVisibleTo() throws {
        let me = UUID(), other = UUID()
        _ = try repo.add(to: meeting, day: Date(), time: nil, title: "公开",
                         note: nil, placeText: nil, authorID: me)
        let mine = try repo.add(to: meeting, day: Date(), time: nil, title: "我的私密",
                                note: nil, placeText: nil, authorID: me,
                                visibility: .privateUntilRevealed)
        try repo.toggleDone(mine)
        XCTAssertEqual(repo.stats(for: meeting).planned, 2)            // nil=全量
        XCTAssertEqual(repo.stats(for: meeting, visibleTo: me).planned, 2)
        XCTAssertEqual(repo.stats(for: meeting, visibleTo: me).done, 1)
        XCTAssertEqual(repo.stats(for: meeting, visibleTo: other).planned, 1)  // 对方看不见我的私密
        XCTAssertEqual(repo.stats(for: meeting, visibleTo: other).done, 0)
        try repo.reveal(mine, at: Date())
        XCTAssertEqual(repo.stats(for: meeting, visibleTo: other).planned, 2)  // 公开后计入
    }
}
