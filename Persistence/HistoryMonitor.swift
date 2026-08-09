import CoreData

protocol MomentNotifying {
    func notifyNewMoments(titles: [String])
    func notifyNewLedgerEntries(count: Int)
    func notifyCycleStart()
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
    private let isLedgerEnabled: () -> Bool
    private let isCycleEnabled: () -> Bool
    /// 在 monitor 的后台 context 队列内被调用，实现只能用传入的 context 取数
    private let myPartnerID: (NSManagedObjectContext) -> UUID?
    private var observer: NSObjectProtocol?
    /// 串行化 processChanges：远程变更通知可能从多线程并发投递，
    /// 无互斥时两次调用会在彼此存 token 前读到同一批事务 → 重复通知（WWDC19 官方模式）。
    private let processQueue = DispatchQueue(label: "HistoryMonitor.process")

    init(container: NSPersistentContainer, localAuthor: String, notifier: MomentNotifying,
         defaults: UserDefaults = .standard,
         isEnabled: @escaping () -> Bool,
         isLedgerEnabled: @escaping () -> Bool,
         isCycleEnabled: @escaping () -> Bool, myPartnerID: @escaping (NSManagedObjectContext) -> UUID?) {
        self.container = container
        self.localAuthor = localAuthor
        self.notifier = notifier
        self.defaults = defaults
        self.isEnabled = isEnabled
        self.isLedgerEnabled = isLedgerEnabled
        self.isCycleEnabled = isCycleEnabled
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
        processQueue.sync {
            let context = container.newBackgroundContext()
            context.performAndWait {
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: loadToken())
                request.resultType = .transactionsAndChanges
                guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
                      let transactions = result.result as? [NSPersistentHistoryTransaction],
                      !transactions.isEmpty else { return }

                var insertedMomentIDs: [NSManagedObjectID] = []
                var ledgerIDs = Set<NSManagedObjectID>()
                var cycleIDs = Set<NSManagedObjectID>()
                for transaction in transactions where transaction.author != localAuthor {
                    for change in transaction.changes ?? [] {
                        let entity = change.changedObjectID.entity.name
                        if change.changeType == .insert && entity == "CDMoment" {
                            insertedMomentIDs.append(change.changedObjectID)
                        }
                        if change.changeType == .insert && entity == "CDCycle" {
                            cycleIDs.insert(change.changedObjectID)
                        }
                        if entity == "CDLedgerEntry" {
                            switch change.changeType {
                            case .insert:
                                ledgerIDs.insert(change.changedObjectID)
                            case .update:
                                if change.updatedProperties?.contains(where: { $0.name == "revealedAt" }) == true {
                                    ledgerIDs.insert(change.changedObjectID)
                                }
                            default: break
                            }
                        }
                    }
                }
                if let last = transactions.last { saveToken(last.token) }

                if isEnabled(), !insertedMomentIDs.isEmpty {
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

                if isLedgerEnabled(), !ledgerIDs.isEmpty {
                    let me = myPartnerID(context)
                    let count = ledgerIDs.reduce(into: 0) { acc, id in
                        guard let entry = try? context.existingObject(with: id) as? CDLedgerEntry else { return }
                        if Self.ledgerNotifiable(authorIsMe: me != nil && entry.authorPartnerID == me,
                                                 visibilityRaw: entry.visibilityRaw,
                                                 revealedAt: entry.revealedAt) { acc += 1 }
                    }
                    if count > 0 { notifier.notifyNewLedgerEntries(count: count) }
                }

                if isCycleEnabled(), !cycleIDs.isEmpty {
                    let me = myPartnerID(context)
                    let started = cycleIDs.contains { id in
                        guard let cycle = try? context.existingObject(with: id) as? CDCycle else { return false }
                        return Self.cycleNotifiable(endDate: cycle.endDate,
                                                    authorPartnerID: cycle.authorPartnerID, myID: me)
                    }
                    if started { notifier.notifyCycleStart() }
                }
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

    /// 对方的公开条目才提醒（可见性判定与 LedgerRules.isRevealed 同构，独立实现避免层次反转）
    nonisolated static func ledgerNotifiable(authorIsMe: Bool, visibilityRaw: Int16,
                                             revealedAt: Date?) -> Bool {
        guard !authorIsMe else { return false }
        return visibilityRaw == EntryVisibility.sharedImmediately.rawValue || revealedAt != nil
    }

    /// 只有「经期开始」（endDate 为空的插入）才提醒；补录起止俱全不惊动（spec §六）。
    /// P6-T2：作者是本机（含自己的第二台设备）不响；author 为 nil（旧数据）仍响，不静默。
    nonisolated static func cycleNotifiable(endDate: Date?, authorPartnerID: UUID?, myID: UUID?) -> Bool {
        guard endDate == nil else { return false }
        if let author = authorPartnerID, let myID, author == myID { return false }
        return true
    }
}
