import XCTest
import CoreData
@testable import Anniversary

private final class SpyNotifier: MomentNotifying {
    var calls: [[String]] = []
    func notifyNewMoments(titles: [String]) { calls.append(titles) }
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

    private func makeMonitor(notifier: SpyNotifier, enabled: Bool = true, me: UUID) -> HistoryMonitor {
        HistoryMonitor(container: container, localAuthor: "AnniversaryApp",
                       notifier: notifier, defaults: defaults,
                       isEnabled: { enabled }, myPartnerID: { _ in me })
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
}
