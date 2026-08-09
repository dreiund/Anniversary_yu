#if DEBUG
import UIKit
import CoreData

/// UI 测试/演示数据种子（仅 DEBUG；`--seed-map-demo` 启动参数触发）。
/// 每次先清空整库再播种——UI 测试反复跑会留下改过状态的旧数据（结束的见面、旧版种子），
/// 靠"空库才种"的幂等挡不住，必须每次从确定状态开始。
/// 种出：情侣 + 进行中见面 + 两条带地点记忆（美食 1 / 景点公园 3）——咖啡甜品等类目恒为空，供筛选空类目复现。
enum DebugSeeder {
    static func seedMapDemoIfEmpty(context: NSManagedObjectContext) {
        // --seed-single-place：只留餐厅一个带地点记忆（反馈⑧bug1 单钉回归场景）
        let singleOnly = ProcessInfo.processInfo.arguments.contains("--seed-single-place")
        wipeAll(context: context)
        let coupleRepo = CoupleRepository(context: context)
        guard (try? coupleRepo.fetchCouple()) == nil else { return }
        guard let couple = try? coupleRepo.bootstrapIfNeeded(
            myName: "阿铖", partnerName: "小于", anniversary: nil) else { return }

        let meetings = MeetingRepository(context: context)
        guard let meeting = try? meetings.createPlanned(
            couple: couple, title: "演示", city: "上海", plannedStart: nil, plannedEnd: nil) else { return }
        try? meetings.start(meeting, at: Date().addingTimeInterval(-3600))

        let restaurant = CDPlace(context: context)
        restaurant.id = UUID()
        restaurant.name = "演示餐厅"
        restaurant.latitude = 31.2304
        restaurant.longitude = 121.4737
        restaurant.categoryRaw = PlaceCategory.food.rawValue
        restaurant.createdAt = Date()
        restaurant.couple = couple

        let park = CDPlace(context: context)
        park.id = UUID()
        park.name = "演示公园"
        park.latitude = 31.2404
        park.longitude = 121.4937
        park.categoryRaw = PlaceCategory.scenery.rawValue
        park.createdAt = Date()
        park.couple = couple

        let moments = MomentRepository(context: context)
        let authorID = coupleRepo.currentPartnerID(of: couple)
        _ = try? moments.create(in: meeting, type: .restaurant, title: "演示午餐", body: nil,
                                happenedAt: Date().addingTimeInterval(-1800), photoDatas: [],
                                myEvaluation: nil, authorID: authorID, place: restaurant)
        _ = try? moments.create(in: meeting, type: .sight, title: "演示散步", body: nil,
                                happenedAt: Date().addingTimeInterval(-900), photoDatas: [],
                                myEvaluation: nil, authorID: authorID, place: singleOnly ? nil : park)
        // 昨天的补录：自动生成一个已封盘的第 1 天（封盘卡左滑删除的验证场景；无地点不进地图）
        _ = try? moments.create(in: meeting, type: .other, title: "演示昨日", body: nil,
                                happenedAt: Date().addingTimeInterval(-90_000), photoDatas: [],
                                myEvaluation: nil, authorID: authorID, place: nil)

        // 带地点的小本本条目：地图「小本本」筛选与角标的演示（逛街类，保持咖啡甜品恒空）
        let bookstore = CDPlace(context: context)
        bookstore.id = UUID()
        bookstore.name = "演示书店"
        bookstore.latitude = 31.2204
        bookstore.longitude = 121.4537
        bookstore.categoryRaw = PlaceCategory.shopping.rawValue
        bookstore.createdAt = Date()
        bookstore.couple = couple
        _ = try? LedgerRepository(context: context).createEntry(
            couple: couple, category: .praise, title: "陪我逛了一下午书店", detail: "全程没催我",
            happenedAt: Date().addingTimeInterval(-600), visibility: .sharedImmediately,
            place: singleOnly ? nil : bookstore,
            evidenceDatas: [solidImageData(.systemTeal), solidImageData(.systemPink)],
            authorID: authorID)

        // 她页种子：被追踪人=小于；两段历史 + 今天进行中 + 点选 + 亲密（截图/演示用）
        let cycleRepo = CycleRepository(context: context)
        let cal = Calendar.current
        if let partner = CoupleRepository(context: context).partners(of: couple)
            .first(where: { $0.name == "小于" }) {
            try? cycleRepo.setTracked(partner, couple: couple)
        }
        let day: (Int) -> Date = { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: Date()))! }
        _ = try? cycleRepo.backfill(couple: couple, start: day(-58), end: day(-53),
                                    today: Date(), calendar: cal)
        _ = try? cycleRepo.backfill(couple: couple, start: day(-30), end: day(-25),
                                    today: Date(), calendar: cal)
        if let current = try? cycleRepo.start(couple: couple, on: day(-1), predictedStart: day(-2),
                                              today: Date(), calendar: cal) {
            _ = try? cycleRepo.setDayLog(in: current, day: day(-1), painRaw: 2, flowRaw: 3,
                                         colorRaw: 3, note: nil, calendar: cal)
            _ = try? cycleRepo.setDayLog(in: current, day: day(0), painRaw: 1, flowRaw: 2,
                                         colorRaw: 2, note: nil, calendar: cal)
        }
        _ = try? cycleRepo.addIntimacy(couple: couple, day: day(-9), protected: true,
                                       note: nil, now: Date(), calendar: cal)
        _ = try? cycleRepo.addIntimacy(couple: couple, day: day(-3), protected: false,
                                       note: nil, now: Date(), calendar: cal)

        // 反馈⑦：计划钉与记得做钉的地点
        let pier = CDPlace(context: context)
        pier.id = UUID(); pier.name = "演示码头"
        pier.latitude = 31.2354; pier.longitude = 121.4837
        pier.categoryRaw = PlaceCategory.other.rawValue
        pier.createdAt = Date(); pier.couple = couple
        _ = try? PlanItemRepository(context: context).add(
            to: meeting, day: Date(), time: nil, title: "去码头拍日落", note: nil,
            placeText: "演示码头", authorID: authorID, place: singleOnly ? nil : pier)

        // 反馈⑧:行前已备划线卡 + 备忘待办(接下来组,两条——一条走点圈/编辑转化用,一条留到结束后当灰卡)
        let ticket = try? PlanItemRepository(context: context).add(
            to: meeting, day: nil, time: nil, title: "买火车票", note: nil,
            placeText: nil, authorID: authorID)
        ticket?.isDone = true
        _ = try? PlanItemRepository(context: context).add(
            to: meeting, day: nil, time: nil, title: "给她妈带特产", note: nil,
            placeText: nil, authorID: authorID)
        _ = try? PlanItemRepository(context: context).add(
            to: meeting, day: nil, time: nil, title: "买伴手礼", note: nil,
            placeText: nil, authorID: authorID)
        try? context.save()

        let florist = CDPlace(context: context)
        florist.id = UUID(); florist.name = "演示花店"
        florist.latitude = 31.2254; florist.longitude = 121.4637
        florist.categoryRaw = PlaceCategory.other.rawValue
        florist.createdAt = Date(); florist.couple = couple

        // 记得做种子：我做一条今天到期 + Ta做一条私密（今天卡/第四段/🔒 演示）
        let todoRepo = TodoRepository(context: context)
        let myID = coupleRepo.currentPartnerID(of: couple)
        let herID = CoupleRepository(context: context).otherPartner(of: couple)?.id
        _ = try? todoRepo.create(couple: couple, title: "帮她带充电宝", detail: nil,
                                 dueAt: Date(), assigneeID: myID, authorID: herID,
                                 visibility: .sharedImmediately, place: singleOnly ? nil : florist, remindAt: nil,
                                 calendar: cal)
        _ = try? todoRepo.create(couple: couple, title: "查演出票", detail: "周五开票",
                                 dueAt: day(3), assigneeID: herID, authorID: myID,
                                 visibility: .privateUntilRevealed, place: nil, remindAt: nil,
                                 calendar: cal)
    }

    /// 清空整库：逐实体逐对象删除。CloudKit 店不支持 NSBatchDeleteRequest（绕过历史追踪会被拒），
    /// 只能对象级删；级联导致的重复删除是无害 no-op，演示库量级极小。
    private static func wipeAll(context: NSManagedObjectContext) {
        let entities = context.persistentStoreCoordinator?.managedObjectModel.entities ?? []
        for entity in entities {
            guard let name = entity.name else { continue }
            let fetch = NSFetchRequest<NSManagedObject>(entityName: name)
            fetch.includesPropertyValues = false
            (try? context.fetch(fetch))?.forEach(context.delete)
        }
        try? context.save()
    }

    /// 纯色演示图（证据/照片占位；Thumbnailer 需要真图，非图字节会得 nil）
    private static func solidImageData(_ color: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 600, height: 450))
            .jpegData(withCompressionQuality: 0.8) { ctx in
                color.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 450))
            }
    }
}
#endif
