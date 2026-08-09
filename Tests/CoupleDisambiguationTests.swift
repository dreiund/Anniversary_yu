import XCTest
import CoreData
@testable import Anniversary

/// P6-B1:双 couple 歧义防线——P2 真实事故是「女友没等邀请自建了单人空间，接受邀请后
/// 两个 CDCouple 并存，fetchCouple 无排序取首个导致身份随机串台」。这里覆盖两条防线：
/// fetchCouple() 的确定性排序、pruneEmptyLocalCouple() 的空壳自愈（绝不误删有数据的 couple）。
///
/// 内存双 store 并非不可行——参照 CurrentPartnerTests 已验证的做法，用独立
/// NSPersistentContainer + 两个本地 sqlite 文件（文件名对齐 PersistenceController 的
/// privateStoreFileName/sharedStoreFileName）即可拿到真实的私有/共享 store 区分，
/// 比 brief 建议的单 store 降级方案覆盖更强，故优先用它；文件末尾另附一个单 store
/// 降级测试，直接对齐 brief 原始方案。
final class CoupleDisambiguationTests: XCTestCase {
    private var tmpDir: URL!
    private var container: NSPersistentContainer!
    private var privateStore: NSPersistentStore!
    private var sharedStore: NSPersistentStore!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        container = NSPersistentContainer(name: "T", managedObjectModel: ModelSchema.model)
        let p = NSPersistentStoreDescription(url: tmpDir.appendingPathComponent(PersistenceController.privateStoreFileName))
        let s = NSPersistentStoreDescription(url: tmpDir.appendingPathComponent(PersistenceController.sharedStoreFileName))
        container.persistentStoreDescriptions = [p, s]
        var loadError: Error?
        container.loadPersistentStores { _, e in if let e { loadError = e } }
        XCTAssertNil(loadError)
        let stores = container.persistentStoreCoordinator.persistentStores
        privateStore = stores.first { $0.url?.lastPathComponent == PersistenceController.privateStoreFileName }
        sharedStore = stores.first { $0.url?.lastPathComponent == PersistenceController.sharedStoreFileName }
    }

    override func tearDownWithError() throws {
        container = nil
        try? FileManager.default.removeItem(at: tmpDir)
    }

    @discardableResult
    private func makeCouple(in store: NSPersistentStore, createdAt: Date) throws -> CDCouple {
        let context = container.viewContext
        let couple = CDCouple(context: context)
        couple.id = UUID(); couple.createdAt = createdAt
        let me = CDPartner(context: context)
        me.id = UUID(); me.name = "阿铖"; me.roleIndex = 0; me.couple = couple
        let her = CDPartner(context: context)
        her.id = UUID(); her.name = "小于"; her.roleIndex = 1; her.couple = couple
        for object in [couple, me, her] as [NSManagedObject] { context.assign(object, to: store) }
        try context.save()
        return couple
    }

    private func addMeeting(to couple: CDCouple, in store: NSPersistentStore) throws {
        let context = container.viewContext
        let meeting = CDMeeting(context: context)
        meeting.id = UUID(); meeting.title = "见面"; meeting.couple = couple
        context.assign(meeting, to: store)
        try context.save()
    }

    private func addMoment(to couple: CDCouple, in store: NSPersistentStore) throws {
        let context = container.viewContext
        let meeting = CDMeeting(context: context)
        meeting.id = UUID(); meeting.title = "见面"; meeting.couple = couple
        let day = CDDateDay(context: context)
        day.id = UUID(); day.meeting = meeting
        let moment = CDMoment(context: context)
        moment.id = UUID(); moment.title = "瞬间"; moment.dateDay = day
        for object in [meeting, day, moment] as [NSManagedObject] { context.assign(object, to: store) }
        try context.save()
    }

    // MARK: - fetchCouple 确定性

    func testFetchCouplePrefersSharedStoreEvenIfCreatedLater() throws {
        try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 1000))
        let laterShared = try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 2000))
        let repo = CoupleRepository(context: container.viewContext)
        XCTAssertEqual(try repo.fetchCouple()?.objectID, laterShared.objectID)
    }

    func testFetchCoupleTiebreaksByEarliestCreatedAtWithinSameStore() throws {
        let earlier = try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 1000))
        try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 2000))
        let repo = CoupleRepository(context: container.viewContext)
        XCTAssertEqual(try repo.fetchCouple()?.objectID, earlier.objectID)
    }

    func testFetchCoupleIsStableAcrossRepeatedCalls() throws {
        try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 500))
        try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 999))
        let repo = CoupleRepository(context: container.viewContext)
        let first = try repo.fetchCouple()
        XCTAssertNotNil(first)
        for _ in 0..<5 {
            XCTAssertEqual(try repo.fetchCouple()?.objectID, first?.objectID)
        }
    }

    /// 单 couple 是全仓最常见场景，确定性化前后行为必须完全不变。
    func testFetchCoupleSingleCoupleUnaffectedRegressionGuard() throws {
        let solo = try makeCouple(in: privateStore, createdAt: Date())
        let repo = CoupleRepository(context: container.viewContext)
        XCTAssertEqual(try repo.fetchCouple()?.objectID, solo.objectID)
    }

    func testFetchCoupleReturnsNilWhenNoCouple() throws {
        let repo = CoupleRepository(context: container.viewContext)
        XCTAssertNil(try repo.fetchCouple())
    }

    // MARK: - pruneEmptyLocalCouple：核心自愈场景（P2 事故复现）

    func testPruneDeletesEmptyPrivateCoupleKeepsSharedWithData() throws {
        try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 100))
        let realShared = try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 50))
        try addMeeting(to: realShared, in: sharedStore)

        let repo = CoupleRepository(context: container.viewContext)
        XCTAssertEqual(try repo.pruneEmptyLocalCouple(), 1)

        let remaining = try container.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(remaining.map(\.objectID), [realShared.objectID])
    }

    func testPruneCascadeDeletesPlaceholderPartnersOfPrunedCouple() throws {
        try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 1))
        let realShared = try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 2))
        try addMeeting(to: realShared, in: sharedStore)

        let repo = CoupleRepository(context: container.viewContext)
        try repo.pruneEmptyLocalCouple()

        let partners = try container.viewContext.fetch(CDPartner.fetchRequest()) as! [CDPartner]
        XCTAssertEqual(partners.count, 2)
        XCTAssertTrue(partners.allSatisfy { $0.couple?.objectID == realShared.objectID })
    }

    func testPruneDeletesEmptyOneWhenBothCouplesArePrivate() throws {
        let empty = try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 1))
        let withData = try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 2))
        try addMeeting(to: withData, in: privateStore)

        let repo = CoupleRepository(context: container.viewContext)
        XCTAssertEqual(try repo.pruneEmptyLocalCouple(), 1)

        let remaining = try container.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(remaining.map(\.objectID), [withData.objectID])
        _ = empty
    }

    /// 唯一、尚未配对的正常新用户场景：绝不能因为「空」就被清掉。
    func testPruneNoOpWhenOnlyOneCoupleExists() throws {
        let solo = try makeCouple(in: privateStore, createdAt: Date())
        let repo = CoupleRepository(context: container.viewContext)
        XCTAssertEqual(try repo.pruneEmptyLocalCouple(), 0)
        let remaining = try container.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(remaining.map(\.objectID), [solo.objectID])
    }

    func testPruneIsIdempotent() throws {
        try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 1))
        let realShared = try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 2))
        try addMeeting(to: realShared, in: sharedStore)

        let repo = CoupleRepository(context: container.viewContext)
        XCTAssertEqual(try repo.pruneEmptyLocalCouple(), 1)
        XCTAssertEqual(try repo.pruneEmptyLocalCouple(), 0)
        let remaining = try container.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(remaining.count, 1)
    }

    func testPruneNeverTouchesSharedStoreCoupleEvenIfEmpty() throws {
        let withData = try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 1))
        try addMeeting(to: withData, in: privateStore)
        let emptyShared = try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 2))

        let repo = CoupleRepository(context: container.viewContext)
        XCTAssertEqual(try repo.pruneEmptyLocalCouple(), 0)
        let remaining = try container.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(Set(remaining.map(\.objectID)), Set([withData.objectID, emptyShared.objectID]))
    }

    // MARK: - pruneEmptyLocalCouple：绝不误删有数据的 couple（逐类核对）

    /// 私有 store 里一个「附带某类数据」的 couple + 共享 store 里另一个空 couple（制造
    /// count > 1 的清理触发条件），断言 pruneEmptyLocalCouple 一个都不删。
    private func assertNotPruned(
        attach: (CDCouple, NSPersistentStore) throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let dataBearing = try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 1))
        try attach(dataBearing, privateStore)
        let sibling = try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 2))

        let repo = CoupleRepository(context: container.viewContext)
        XCTAssertEqual(try repo.pruneEmptyLocalCouple(), 0, file: file, line: line)

        let remaining = try container.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(Set(remaining.map(\.objectID)), Set([dataBearing.objectID, sibling.objectID]),
                        file: file, line: line)
    }

    func testPruneKeepsCoupleWithMeetingData() throws {
        try assertNotPruned { couple, store in try self.addMeeting(to: couple, in: store) }
    }

    func testPruneKeepsCoupleWithMomentData() throws {
        try assertNotPruned { couple, store in try self.addMoment(to: couple, in: store) }
    }

    func testPruneKeepsCoupleWithLedgerEntryData() throws {
        try assertNotPruned { couple, store in
            let context = self.container.viewContext
            let entry = CDLedgerEntry(context: context)
            entry.id = UUID(); entry.title = "花销"; entry.couple = couple
            context.assign(entry, to: store)
            try context.save()
        }
    }

    func testPruneKeepsCoupleWithTodoData() throws {
        try assertNotPruned { couple, store in
            let context = self.container.viewContext
            let todo = CDTodoItem(context: context)
            todo.id = UUID(); todo.title = "记得做"; todo.couple = couple
            context.assign(todo, to: store)
            try context.save()
        }
    }

    func testPruneKeepsCoupleWithCycleData() throws {
        try assertNotPruned { couple, store in
            let context = self.container.viewContext
            let cycle = CDCycle(context: context)
            cycle.id = UUID(); cycle.startDate = Date(); cycle.couple = couple
            context.assign(cycle, to: store)
            try context.save()
        }
    }

    func testPruneKeepsCoupleWithPlaceData() throws {
        try assertNotPruned { couple, store in
            let context = self.container.viewContext
            let place = CDPlace(context: context)
            place.id = UUID(); place.name = "家"; place.couple = couple
            context.assign(place, to: store)
            try context.save()
        }
    }

    func testPruneKeepsCoupleWithDailyMoodData() throws {
        try assertNotPruned { couple, store in
            let context = self.container.viewContext
            let mood = CDDailyMood(context: context)
            mood.id = UUID(); mood.day = Date(); mood.couple = couple
            context.assign(mood, to: store)
            try context.save()
        }
    }

    func testPruneKeepsCoupleWithIntimacyRecordData() throws {
        try assertNotPruned { couple, store in
            let context = self.container.viewContext
            let record = CDIntimacyRecord(context: context)
            record.id = UUID(); record.happenedAt = Date(); record.couple = couple
            context.assign(record, to: store)
            try context.save()
        }
    }

    // MARK: - 单 store 降级方案（对齐 brief 原始测试计划）

    /// brief 原计划：内存双 store 不可行时用单 store 模拟。实测下用独立 NSPersistentContainer
    /// 可以拿到真双 store（上面全部用例），但 PersistenceController(inMemory: true) 本身
    /// （生产代码实际会用到的单 store 场景，见 PersistenceControllerTests）确实只给单 store，
    /// 这里直接对着它跑一遍，确认两条防线在这个降级形态下同样成立。
    func testFetchAndPruneUsingSingleInMemoryStoreDegradedSetup() throws {
        let pc = PersistenceController(inMemory: true)
        let repo = CoupleRepository(context: pc.viewContext)

        let hasData = try repo.bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        hasData.createdAt = Date(timeIntervalSince1970: 1)
        let meeting = CDMeeting(context: pc.viewContext)
        meeting.id = UUID(); meeting.title = "见面"; meeting.couple = hasData

        let empty = CDCouple(context: pc.viewContext)
        empty.id = UUID(); empty.createdAt = Date(timeIntervalSince1970: 2)
        let me = CDPartner(context: pc.viewContext)
        me.id = UUID(); me.roleIndex = 0; me.couple = empty
        let her = CDPartner(context: pc.viewContext)
        her.id = UUID(); her.roleIndex = 1; her.couple = empty
        try pc.viewContext.save()

        // 单 store 无私有/共享区分，退化为 createdAt 最早——多次调用一致，且恰好是有数据那个。
        let first = try repo.fetchCouple()
        XCTAssertEqual(first?.objectID, hasData.objectID)
        XCTAssertEqual(try repo.fetchCouple()?.objectID, first?.objectID)

        XCTAssertEqual(try repo.pruneEmptyLocalCouple(), 1)
        let remaining = try pc.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(remaining.map(\.objectID), [hasData.objectID])
    }
}
