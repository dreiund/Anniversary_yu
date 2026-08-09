import XCTest
@testable import Anniversary

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
        // 先 start 进 ongoing：convertToMoment 内部走 MomentRepository.create → dayForRecord 才有天可归
        try meetings.start(meeting, at: date(2026, 8, 29))
        plans = PlanItemRepository(context: pc.viewContext)
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // 1. 字段映射：标题/正文/过去时刻用计划时刻/类目→类型/地点原样带过去；源计划项被删（防重）
    func testConvertMapsFields() throws {
        let place = CDPlace(context: pc.viewContext)
        place.id = UUID()
        place.name = "蟹家大院"
        place.categoryRaw = PlaceCategory.food.rawValue
        place.createdAt = Date()
        place.couple = couple

        let item = try plans.add(to: meeting, day: date(2026, 8, 30), time: date(2026, 8, 30, 10, 0),
                                 title: "吃蟹家大院", note: "人多要排队", placeText: nil,
                                 authorID: nil, place: place)

        let moment = try plans.convertToMoment(item, now: date(2026, 8, 30, 14, 0))

        let m = try XCTUnwrap(moment)
        XCTAssertEqual(m.title, "吃蟹家大院")
        XCTAssertEqual(m.body, "人多要排队")
        XCTAssertEqual(m.happenedAt, date(2026, 8, 30, 10, 0), "过去时刻应使用计划时刻，而非 now")
        XCTAssertEqual(m.typeRaw, MomentType.restaurant.rawValue, "food 类目应映射成 restaurant")
        XCTAssertEqual(m.place?.objectID, place.objectID, "原 place 应原样带过去")
        XCTAssertEqual(plans.stats(for: meeting).planned, 0, "源计划项应被删除，防止重复转化")
    }

    // 2. 未来计划时刻钳到 now，避免 dayForRecord 造出「未来已封盘天」
    func testConvertClampsFutureToNow() throws {
        let item = try plans.add(to: meeting, day: date(2026, 9, 2), time: date(2026, 9, 2, 18, 0),
                                 title: "音乐节", note: nil, placeText: nil, authorID: nil)

        let now = date(2026, 9, 1, 12, 0)
        let moment = try plans.convertToMoment(item, now: now)

        XCTAssertEqual(moment?.happenedAt, now, "未来的计划时刻必须钳到 now")
    }

    // 3. 无日期备忘：happenedAt 落到 now，类目缺失映射到 other
    func testConvertMemoWithoutDate() throws {
        let item = try plans.add(to: meeting, day: nil, time: nil,
                                 title: "带充电宝", note: nil, placeText: nil, authorID: nil)

        let now = date(2026, 8, 30, 9, 0)
        let moment = try plans.convertToMoment(item, now: now)

        XCTAssertEqual(moment?.happenedAt, now, "无日期备忘应落到 now")
        XCTAssertEqual(moment?.typeRaw, MomentType.other.rawValue, "无地点应映射到 other")
    }

    // 4. 手输文字地点走 PlaceResolver 同管线归并出无坐标地点
    func testConvertResolvesPlaceText() throws {
        let item = try plans.add(to: meeting, day: date(2026, 8, 30), time: nil,
                                 title: "面馆", note: nil, placeText: "老巷面馆", authorID: nil)

        let moment = try plans.convertToMoment(item, now: date(2026, 8, 30, 20, 0))

        let place = try XCTUnwrap(moment?.place, "placeText 应归并出一个 CDPlace")
        XCTAssertEqual(place.name, "老巷面馆")
    }

    // 5. plannedMoment 合成：day 只取年月日，time 只取时分；全天用 00:00；无日期 nil
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
}
