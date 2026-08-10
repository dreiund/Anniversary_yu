import XCTest
import CoreData
@testable import Anniversary

/// P6-B1:双 couple 歧义防线——P2 真实事故是「女友没等邀请自建了单人空间，接受邀请后
/// 两个 CDCouple 并存，fetchCouple 无排序取首个导致身份随机串台」。这里覆盖两条防线：
/// fetchCouple() 的确定性排序、pruneEmptyLocalCouple() 的空壳自愈。
///
/// pruneEmptyLocalCouple 的判据经过评审裁决改为「本机创建标记」而非直接判空——私有 store
/// 同样挂 CloudKit 同步，换机/重装后一个正在同步、子数据还没落地的真实 couple 会在窗口期里
/// 「看起来是空的」，纯判空会把它跟真的空壳混为一谈而误删（且删除会同步回云端）。标记只在
/// bootstrapIfNeeded 本机就地新建 couple 那一刻写入，结构上不可能落到远端同步来的 couple 上，
/// 所以下面大量用例都先显式调 `mark(_:)` 模拟这枚标记，而不是单纯造一个「空」couple。
///
/// 内存双 store 并非不可行——参照 CurrentPartnerTests 已验证的做法，用独立
/// NSPersistentContainer + 两个本地 sqlite 文件（文件名对齐 PersistenceController 的
/// privateStoreFileName/sharedStoreFileName）即可拿到真实的私有/共享 store 区分，
/// 比 brief 建议的单 store 降级方案覆盖更强，故优先用它；文件末尾另附一个单 store
/// 降级测试，直接对齐 brief 原始方案，并按真实时序复现 P2 事故（先本机 bootstrap 出一个
/// 空壳并打标记，再让「真实」couple 后到）。
final class CoupleDisambiguationTests: XCTestCase {
    private var tmpDir: URL!
    private var container: NSPersistentContainer!
    private var privateStore: NSPersistentStore!
    private var sharedStore: NSPersistentStore!
    private var defaults: UserDefaults!
    private let suite = "CoupleDisambiguationTests"

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
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        container = nil
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func repo() -> CoupleRepository {
        CoupleRepository(context: container.viewContext, defaults: defaults)
    }

    /// 模拟 bootstrapIfNeeded 落下的「本机创建标记」——真实生产里这一步由 bootstrapIfNeeded
    /// 自动完成，这里为了精确控场（哪个 couple 该被判定为本机自建）显式调用。
    private func mark(_ couple: CDCouple) {
        defaults.set(couple.id!.uuidString, forKey: CoupleRepository.locallyBootstrappedCoupleIDKey)
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

    /// 附带完整 meeting→dateDay→moment 三级链——同时覆盖「有 moment 就必然有 meeting」这条
    /// 结构性事实(hasAnyData 只查 meetings，不单独查 moments，见 CoupleRepository 注释)。
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
        XCTAssertEqual(try repo().fetchCouple()?.objectID, laterShared.objectID)
    }

    func testFetchCoupleTiebreaksByEarliestCreatedAtWithinSameStore() throws {
        let earlier = try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 1000))
        try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(try repo().fetchCouple()?.objectID, earlier.objectID)
    }

    func testFetchCoupleIsStableAcrossRepeatedCalls() throws {
        try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 500))
        try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 999))
        let r = repo()
        let first = try r.fetchCouple()
        XCTAssertNotNil(first)
        for _ in 0..<5 {
            XCTAssertEqual(try r.fetchCouple()?.objectID, first?.objectID)
        }
    }

    /// 单 couple 是全仓最常见场景，确定性化前后行为必须完全不变。
    func testFetchCoupleSingleCoupleUnaffectedRegressionGuard() throws {
        let solo = try makeCouple(in: privateStore, createdAt: Date())
        XCTAssertEqual(try repo().fetchCouple()?.objectID, solo.objectID)
    }

    func testFetchCoupleReturnsNilWhenNoCouple() throws {
        XCTAssertNil(try repo().fetchCouple())
    }

    // MARK: - pruneEmptyLocalCouple：核心自愈场景（P2 事故复现，标记版）

    func testPruneDeletesMarkedEmptyCoupleKeepsSharedWithData() throws {
        let empty = try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 100))
        mark(empty)
        let realShared = try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 50))
        try addMeeting(to: realShared, in: sharedStore)

        XCTAssertEqual(try repo().pruneEmptyLocalCouple(), 1)

        let remaining = try container.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(remaining.map(\.objectID), [realShared.objectID])
        XCTAssertNil(defaults.string(forKey: CoupleRepository.locallyBootstrappedCoupleIDKey))
    }

    /// 评审裁决要修的高危场景：私有 store 里一个「看起来空」的 couple——如果它没有本机创建
    /// 标记（意味着它不是本机 bootstrap 出来的，而可能是换机/重装后正在从 CloudKit 同步、
    /// 子数据还没落地的真实 couple），绝不能被删。这是本轮修复要防的核心事故。
    func testPruneKeepsUnmarkedEmptyPrivateCouple() throws {
        let unmarkedEmpty = try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 1))
        let sibling = try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 2))
        try addMeeting(to: sibling, in: sharedStore)

        XCTAssertEqual(try repo().pruneEmptyLocalCouple(), 0)

        let remaining = try container.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(Set(remaining.map(\.objectID)), Set([unmarkedEmpty.objectID, sibling.objectID]))
    }

    func testPruneCascadeDeletesPlaceholderPartnersOfPrunedCouple() throws {
        let empty = try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 1))
        mark(empty)
        let realShared = try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 2))
        try addMeeting(to: realShared, in: sharedStore)

        try repo().pruneEmptyLocalCouple()

        let partners = try container.viewContext.fetch(CDPartner.fetchRequest()) as! [CDPartner]
        XCTAssertEqual(partners.count, 2)
        XCTAssertTrue(partners.allSatisfy { $0.couple?.objectID == realShared.objectID })
    }

    /// 唯一、尚未配对的正常新用户场景：即便它带着标记，只要总数只有 1 个也绝不能被清掉。
    func testPruneNoOpWhenOnlyOneCoupleExists() throws {
        let solo = try makeCouple(in: privateStore, createdAt: Date())
        mark(solo)
        XCTAssertEqual(try repo().pruneEmptyLocalCouple(), 0)
        let remaining = try container.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(remaining.map(\.objectID), [solo.objectID])
    }

    func testPruneIsIdempotent() throws {
        let empty = try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 1))
        mark(empty)
        let realShared = try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 2))
        try addMeeting(to: realShared, in: sharedStore)

        let r = repo()
        XCTAssertEqual(try r.pruneEmptyLocalCouple(), 1)
        XCTAssertEqual(try r.pruneEmptyLocalCouple(), 0) // 标记已清，第二次天然 no-op
        let remaining = try container.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(remaining.count, 1)
    }

    /// 防御性用例：标记理论上只可能指向私有 store 的 couple（bootstrapIfNeeded 的产物），
    /// 但即便未来某个 bug 让它指向了共享 store 的 couple，isParticipantDevice 双保险也必须拦住。
    func testPruneNeverTouchesSharedStoreCoupleEvenIfMarked() throws {
        let withData = try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 1))
        try addMeeting(to: withData, in: privateStore)
        let emptyShared = try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 2))
        mark(emptyShared)

        XCTAssertEqual(try repo().pruneEmptyLocalCouple(), 0)
        let remaining = try container.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(Set(remaining.map(\.objectID)), Set([withData.objectID, emptyShared.objectID]))
    }

    func testPruneNoOpWhenMarkerPointsToNonexistentCouple() throws {
        defaults.set(UUID().uuidString, forKey: CoupleRepository.locallyBootstrappedCoupleIDKey)
        try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 1))
        try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(try repo().pruneEmptyLocalCouple(), 0)
        let remaining = try container.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(remaining.count, 2)
    }

    // MARK: - pruneEmptyLocalCouple：即便带标记，也绝不误删有数据的 couple（逐类核对）

    /// 私有 store 里一枚带标记的 couple + 共享 store 里另一个 couple（制造 count>1 的清理
    /// 触发条件），断言只要标记指向的 couple 有任意一类数据，pruneEmptyLocalCouple 就不删。
    private func assertMarkedCoupleSurvives(
        attach: (CDCouple, NSPersistentStore) throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let dataBearing = try makeCouple(in: privateStore, createdAt: Date(timeIntervalSince1970: 1))
        mark(dataBearing)
        try attach(dataBearing, privateStore)
        let sibling = try makeCouple(in: sharedStore, createdAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(try repo().pruneEmptyLocalCouple(), 0, file: file, line: line)

        let remaining = try container.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(Set(remaining.map(\.objectID)), Set([dataBearing.objectID, sibling.objectID]),
                        file: file, line: line)
    }

    /// meeting 与 moment 二合一：moment 结构上必须挂在某个 meeting 下，加 moment 必然同时
    /// 让 couple.meetings 非空，两者在 hasAnyData 里走的是同一条判断，不必分成两个用例。
    func testPruneKeepsMarkedCoupleWithMeetingOrMomentData() throws {
        try assertMarkedCoupleSurvives { couple, store in try self.addMoment(to: couple, in: store) }
    }

    func testPruneKeepsMarkedCoupleWithLedgerEntryData() throws {
        try assertMarkedCoupleSurvives { couple, store in
            let context = self.container.viewContext
            let entry = CDLedgerEntry(context: context)
            entry.id = UUID(); entry.title = "花销"; entry.couple = couple
            context.assign(entry, to: store)
            try context.save()
        }
    }

    func testPruneKeepsMarkedCoupleWithTodoData() throws {
        try assertMarkedCoupleSurvives { couple, store in
            let context = self.container.viewContext
            let todo = CDTodoItem(context: context)
            todo.id = UUID(); todo.title = "待办"; todo.couple = couple
            context.assign(todo, to: store)
            try context.save()
        }
    }

    func testPruneKeepsMarkedCoupleWithCycleData() throws {
        try assertMarkedCoupleSurvives { couple, store in
            let context = self.container.viewContext
            let cycle = CDCycle(context: context)
            cycle.id = UUID(); cycle.startDate = Date(); cycle.couple = couple
            context.assign(cycle, to: store)
            try context.save()
        }
    }

    func testPruneKeepsMarkedCoupleWithPlaceData() throws {
        try assertMarkedCoupleSurvives { couple, store in
            let context = self.container.viewContext
            let place = CDPlace(context: context)
            place.id = UUID(); place.name = "家"; place.couple = couple
            context.assign(place, to: store)
            try context.save()
        }
    }

    func testPruneKeepsMarkedCoupleWithDailyMoodData() throws {
        try assertMarkedCoupleSurvives { couple, store in
            let context = self.container.viewContext
            let mood = CDDailyMood(context: context)
            mood.id = UUID(); mood.day = Date(); mood.couple = couple
            context.assign(mood, to: store)
            try context.save()
        }
    }

    func testPruneKeepsMarkedCoupleWithIntimacyRecordData() throws {
        try assertMarkedCoupleSurvives { couple, store in
            let context = self.container.viewContext
            let record = CDIntimacyRecord(context: context)
            record.id = UUID(); record.happenedAt = Date(); record.couple = couple
            context.assign(record, to: store)
            try context.save()
        }
    }

    // MARK: - 单 store 降级方案（对齐 brief 原始测试计划，按真实时序复现 P2 事故）

    /// brief 原计划：内存双 store 不可行时用单 store 模拟。实测下用独立 NSPersistentContainer
    /// 可以拿到真双 store（上面全部用例），但 PersistenceController(inMemory: true) 本身
    /// （生产代码实际会用到的单 store 场景，见 PersistenceControllerTests）确实只给单 store，
    /// 这里直接对着它跑一遍，并按 P2 真实时序构造：先用 bootstrapIfNeeded 在本机就地建一个
    /// 空壳（自动打标记，此刻库里只有它一个，prune 不动它）；再模拟「真实」couple 后到
    /// （单 store 下没法真放进另一个 sqlite 文件，直接插入模拟同步落地）；最后一次 prune
    /// 才应该把本机那个空壳标记着的 couple 收敛掉。
    func testFetchAndPruneUsingSingleInMemoryStoreDegradedSetup() throws {
        let pc = PersistenceController(inMemory: true)
        let r = CoupleRepository(context: pc.viewContext, defaults: defaults)

        let selfCreatedEmpty = try r.bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        selfCreatedEmpty.createdAt = Date(timeIntervalSince1970: 2)

        // 此刻库里只有本机自建的这一个（哪怕带标记），count==1，prune 绝不动它。
        XCTAssertEqual(try r.pruneEmptyLocalCouple(), 0)

        // 「真实」couple 后到（模拟接受邀请后镜像导入落地，且已有数据）——不经 bootstrapIfNeeded，
        // 天然不带标记。
        let real = CDCouple(context: pc.viewContext)
        real.id = UUID(); real.createdAt = Date(timeIntervalSince1970: 1)
        let me = CDPartner(context: pc.viewContext)
        me.id = UUID(); me.roleIndex = 0; me.couple = real
        let her = CDPartner(context: pc.viewContext)
        her.id = UUID(); her.roleIndex = 1; her.couple = real
        let meeting = CDMeeting(context: pc.viewContext)
        meeting.id = UUID(); meeting.title = "见面"; meeting.couple = real
        try pc.viewContext.save()

        // 单 store 无私有/共享区分，fetchCouple 退化为 createdAt 最早——多次调用一致。
        let first = try r.fetchCouple()
        XCTAssertEqual(first?.objectID, real.objectID)
        XCTAssertEqual(try r.fetchCouple()?.objectID, first?.objectID)

        // 现在 count==2，标记指向的 selfCreatedEmpty 仍然空——这一次 prune 才会收敛它。
        XCTAssertEqual(try r.pruneEmptyLocalCouple(), 1)
        let remaining = try pc.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(remaining.map(\.objectID), [real.objectID])
    }
}
