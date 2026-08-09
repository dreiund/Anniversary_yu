import XCTest
@testable import Anniversary

/// 反馈⑨T5: 待办转化逻辑单元测试。
/// 转化唯一入口收敛为 MomentFormView.fromPlan 表单（反馈⑨ 2A），端到端由 UI 用例锁。
/// 本文件保留 plannedMoment 时刻合成与 MomentType 类目映射的单测。
final class PlanConversionTests: XCTestCase {
    private var pc: PersistenceController!
    private var couple: CDCouple!
    private var meeting: CDMeeting!
    private var plans: PlanItemRepository!
    private let cal = Calendar(identifier: .gregorian)

    override func setUpWithError() throws {
        pc = PersistenceController(inMemory: true)
        let couples = CoupleRepository(context: pc.viewContext)
        couple = try couples.bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        let meetings = MeetingRepository(context: pc.viewContext)
        meeting = try meetings.createPlanned(couple: couple, title: nil, city: "上海",
                                             plannedStart: nil, plannedEnd: nil)
        try meetings.start(meeting, at: date(2026, 8, 29))
        plans = PlanItemRepository(context: pc.viewContext)
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // 1. plannedMoment 合成：day 只取年月日，time 只取时分；全天用 00:00；无日期 nil
    func testPlannedMomentComposition() throws {
        let day = date(2026, 8, 12, 23, 0)      // 年月日之外的时分不该被采用
        let time = date(2026, 9, 5, 18, 30)     // 另一天——只取其时分

        let withTime = CDPlanItem(context: pc.viewContext)
        withTime.day = day
        withTime.time = time
        XCTAssertEqual(plans.plannedMoment(of: withTime, calendar: cal), date(2026, 8, 12, 18, 30))

        let allDay = CDPlanItem(context: pc.viewContext)
        allDay.day = day
        XCTAssertEqual(plans.plannedMoment(of: allDay, calendar: cal), cal.startOfDay(for: day))

        let memo = CDPlanItem(context: pc.viewContext)
        XCTAssertNil(plans.plannedMoment(of: memo, calendar: cal))
    }

    // 2. 评审补测：MomentType(placeCategory:) 直接遍历全部 7 个 PlaceCategory case 逐一断言，
    //    防止遗漏或误改任何分支
    func testMomentTypeMappingCoversAllCategories() throws {
        let expectations: [(PlaceCategory, MomentType)] = [
            (.other, .other),
            (.food, .restaurant),
            (.cafe, .restaurant),
            (.scenery, .sight),
            (.shopping, .activity),
            (.show, .activity),
            (.stay, .stay),
        ]
        XCTAssertEqual(PlaceCategory.allCases.count, expectations.count,
                       "PlaceCategory 增删 case 时本测试要同步更新，别漏分支")
        for (category, want) in expectations {
            XCTAssertEqual(MomentType(placeCategory: category).rawValue, want.rawValue,
                           "\(category) 应映射到 \(want)")
        }
    }

}
