import CoreData

protocol MomentNotifying {
    func notifyNewMoments(titles: [String])
}

/// 远程导入监听：镜像把对方的写入合进本地库时（NSPersistentStoreRemoteChange），
/// 从 persistent history 里挑出「事务作者 ≠ 本机」的新增 CDMoment 发本地通知。
/// App 未被唤醒时通知会迟到，首页提醒区（数据驱动）兜底——尽力而为，不做保证。
final class HistoryMonitor {
    static let tokenKey = "historyMonitor.token.v1"

    private let container: NSPersistentContainer
    private let localAuthor: String
    private let notifier: MomentNotifying
    private let defaults: UserDefaults
    private let isEnabled: () -> Bool
    /// 在 monitor 的后台 context 队列内被调用，实现只能用传入的 context 取数
    private let myPartnerID: (NSManagedObjectContext) -> UUID?
    private var observer: NSObjectProtocol?

    init(container: NSPersistentContainer, localAuthor: String, notifier: MomentNotifying,
         defaults: UserDefaults = .standard,
         isEnabled: @escaping () -> Bool, myPartnerID: @escaping (NSManagedObjectContext) -> UUID?) {
        self.container = container
        self.localAuthor = localAuthor
        self.notifier = notifier
        self.defaults = defaults
        self.isEnabled = isEnabled
        self.myPartnerID = myPartnerID
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator, queue: nil) { [weak self] _ in
            self?.processChanges()
        }
    }

    func processChanges() {
        let context = container.newBackgroundContext()
        context.performAndWait {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: loadToken())
            request.resultType = .transactionsAndChanges
            guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction],
                  !transactions.isEmpty else { return }

            var insertedMomentIDs: [NSManagedObjectID] = []
            for transaction in transactions where transaction.author != localAuthor {
                for change in transaction.changes ?? []
                where change.changeType == .insert && change.changedObjectID.entity.name == "CDMoment" {
                    insertedMomentIDs.append(change.changedObjectID)
                }
            }
            if let last = transactions.last { saveToken(last.token) }

            guard isEnabled(), !insertedMomentIDs.isEmpty else { return }
            let me = myPartnerID(context)
            let titles: [String] = insertedMomentIDs.compactMap { id in
                guard let moment = try? context.existingObject(with: id) as? CDMoment else { return nil }
                if let me, moment.authorPartnerID == me { return nil }  // 自己另一台设备写的不提醒
                return moment.title ?? "新回忆"
            }
            if !titles.isEmpty {
                notifier.notifyNewMoments(titles: titles)
            }
        }
    }

    private func loadToken() -> NSPersistentHistoryToken? {
        guard let data = defaults.data(forKey: Self.tokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
    }

    private func saveToken(_ token: NSPersistentHistoryToken) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        defaults.set(data, forKey: Self.tokenKey)
    }
}
