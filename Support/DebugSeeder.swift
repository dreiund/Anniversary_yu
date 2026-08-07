#if DEBUG
import Foundation
import CoreData

/// UI 测试/演示数据种子（仅 DEBUG；`--seed-map-demo` 启动参数触发；空库才种，幂等）。
/// 种出：情侣 + 进行中见面 + 两条带地点记忆（美食 1 / 景点公园 3）——咖啡甜品等类目恒为空，供筛选空类目复现。
enum DebugSeeder {
    static func seedMapDemoIfEmpty(context: NSManagedObjectContext) {
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
                                myEvaluation: nil, authorID: authorID, place: park)

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
            place: bookstore, evidenceDatas: [], authorID: authorID)
    }
}
#endif
