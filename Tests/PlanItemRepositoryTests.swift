import XCTest
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
        try repo.update(a, day: date(2026, 8, 29), time: nil, title: "新", note: "备注", placeText: "湖滨路店", remindAt: nil)
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
}
