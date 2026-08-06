import XCTest
import CoreData
@testable import Anniversary

private final class SpyNotifier: MomentNotifying {
    var calls: [[String]] = []
    var ledgerCounts: [Int] = []
    func notifyNewMoments(titles: [String]) { calls.append(titles) }
    func notifyNewLedgerEntries(count: Int) { ledgerCounts.append(count) }
}

final class HistoryMonitorTests: XCTestCase {
    private var tmpDir: URL!
    private var container: NSPersistentContainer!
    private var defaults: UserDefaults!
    private let suite = "HistoryMonitorTests"

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        container = NSPersistentContainer(name: "T", managedObjectModel: ModelSchema.model)
        let desc = NSPersistentStoreDescription(url: tmpDir.appendingPathComponent("t.sqlite"))
        desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, e in if let e { loadError = e } }
        XCTAssertNil(loadError)
        container.viewContext.transactionAuthor = "AnniversaryApp"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        container = nil
        try? FileManager.default.removeItem(at: tmpDir)
    }

    /// 造一条“像镜像导入”的事务：后台 context、作者不是本机
    private func importPartnerMoment(title: String, author authorID: UUID) throws {
        let bg = container.newBackgroundContext()
        bg.transactionAuthor = "NSCloudKitMirroringDelegate.import"
        var thrown: Error?
        bg.performAndWait {
            let moment = CDMoment(context: bg)
            moment.id = UUID()
            moment.title = title
            moment.typeRaw = 0
            moment.createdAt = Date()
            moment.authorPartnerID = authorID
            do { try bg.save() } catch { thrown = error }
        }
        if let thrown { throw thrown }
    }

    /// 造一条“像镜像导入”的小本本条目事务：后台 context、作者不是本机
    @discardableResult
    private func importPartnerLedgerEntry(title: String, visibilityRaw: Int16, revealedAt: Date? = nil,
                                          author authorID: UUID) throws -> UUID {
        let id = UUID()
        let bg = container.newBackgroundContext()
        bg.transactionAuthor = "NSCloudKitMirroringDelegate.import"
        var thrown: Error?
        bg.performAndWait {
            let entry = CDLedgerEntry(context: bg)
            entry.id = id
            entry.categoryRaw = LedgerCategory.like.rawValue
            entry.title = title
            entry.visibilityRaw = visibilityRaw
            entry.createdAt = Date()
            entry.happenedAt = Date()
            entry.authorPartnerID = authorID
            entry.revealedAt = revealedAt
            let couple = CDCouple(context: bg)
            couple.id = UUID()
            entry.couple = couple
            do { try bg.save() } catch { thrown = error }
        }
        if let thrown { throw thrown }
        return id
    }

    /// 对既有条目在新事务里补写 revealedAt（同镜像导入：后台 context、作者不是本机）——
    /// 用来在同一 processChanges 批次里凑出“插入 + 更新同一对象”的 history
    private func revealPartnerLedgerEntry(id: UUID, at date: Date) throws {
        let bg = container.newBackgroundContext()
        bg.transactionAuthor = "NSCloudKitMirroringDelegate.import"
        var thrown: Error?
        bg.performAndWait {
            let req = NSFetchRequest<CDLedgerEntry>(entityName: "CDLedgerEntry")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            req.fetchLimit = 1
            guard let entry = (try? bg.fetch(req))?.first else { return }
            entry.revealedAt = date
            do { try bg.save() } catch { thrown = error }
        }
        if let thrown { throw thrown }
    }

    private func makeMonitor(notifier: SpyNotifier, enabled: Bool = true, ledgerEnabled: Bool = true,
                             me: UUID) -> HistoryMonitor {
        HistoryMonitor(container: container, localAuthor: "AnniversaryApp",
                       notifier: notifier, defaults: defaults,
                       isEnabled: { enabled }, isLedgerEnabled: { ledgerEnabled }, myPartnerID: { _ in me })
    }

    func testPartnerImportTriggersNotificationOnce() throws {
        let me = UUID(), her = UUID()
        let spy = SpyNotifier()
        let monitor = makeMonitor(notifier: spy, me: me)
        try importPartnerMoment(title: "外滩夜景", author: her)
        monitor.processChanges()
        XCTAssertEqual(spy.calls, [["外滩夜景"]])
        monitor.processChanges()
        XCTAssertEqual(spy.calls.count, 1, "token 前进后不得重复通知")
    }

    func testOwnLocalWritesDoNotNotify() throws {
        let me = UUID()
        let spy = SpyNotifier()
        let monitor = makeMonitor(notifier: spy, me: me)
        let moment = CDMoment(context: container.viewContext)
        moment.id = UUID(); moment.title = "我自己记的"; moment.typeRaw = 0
        moment.createdAt = Date(); moment.authorPartnerID = me
        try container.viewContext.save()
        monitor.processChanges()
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testDisabledStillAdvancesTokenSilently() throws {
        let me = UUID(), her = UUID()
        let spy = SpyNotifier()
        let muted = makeMonitor(notifier: spy, enabled: false, me: me)
        try importPartnerMoment(title: "静音期记录", author: her)
        muted.processChanges()
        XCTAssertTrue(spy.calls.isEmpty)
        let loud = makeMonitor(notifier: spy, enabled: true, me: me)
        try importPartnerMoment(title: "开启后记录", author: her)
        loud.processChanges()
        XCTAssertEqual(spy.calls, [["开启后记录"]], "静音期条目不补发，token 已消化")
    }

    // spec §三.6/§九：对方公开插入才提醒；私密插入不提醒；同批插入+更新同一条目靠 Set 去重只计一次
    func testPartnerLedgerInsertAndRevealNotifications() throws {
        let me = UUID(), her = UUID()
        let spy = SpyNotifier()
        let monitor = makeMonitor(notifier: spy, me: me)

        // 对方作者插入公开条目 → 计入通知
        try importPartnerLedgerEntry(title: "公开喜悦", visibilityRaw: EntryVisibility.sharedImmediately.rawValue,
                                     author: her)
        monitor.processChanges()
        XCTAssertEqual(spy.ledgerCounts, [1])

        // 对方作者插入私密条目（revealedAt=nil）→ 不新增通知
        try importPartnerLedgerEntry(title: "私密吐槽", visibilityRaw: EntryVisibility.privateUntilRevealed.rawValue,
                                     author: her)
        monitor.processChanges()
        XCTAssertEqual(spy.ledgerCounts, [1], "私密未公开不得计入")

        // 同批：插入即公开 + 又置 revealedAt 落在同一条目上 → Set 去重仍只计 1
        let id = try importPartnerLedgerEntry(title: "又公开又补 reveal",
                                              visibilityRaw: EntryVisibility.sharedImmediately.rawValue, author: her)
        try revealPartnerLedgerEntry(id: id, at: Date())
        monitor.processChanges()
        XCTAssertEqual(spy.ledgerCounts, [1, 1], "同一条目的插入与更新落在同一批次内只应计 1 次")
    }
}
