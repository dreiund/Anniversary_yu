import CoreData
import CloudKit

final class PersistenceController {
    static let shared = PersistenceController()

    static let cloudContainerID = "iCloud.com.fkc.anniversary"
    static let localTransactionAuthor = "AnniversaryApp"
    static let privateStoreFileName = "Anniversary.sqlite"
    static let sharedStoreFileName = "Anniversary-shared.sqlite"

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// inMemory 保持 P0/P1 的单 store（/dev/null、无云选项），既有测试前提不变；
    /// 磁盘路径为 私有+共享 双 store，文件名是身份解析的依据（CoupleRepository）。
    static func makeStoreDescriptions(inMemory: Bool, directory: URL) -> [NSPersistentStoreDescription] {
        if inMemory {
            let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            description.cloudKitContainerOptions = nil
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            return [description]
        }
        let privateDescription = NSPersistentStoreDescription(url: directory.appendingPathComponent(privateStoreFileName))
        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudContainerID)
        privateOptions.databaseScope = .private
        privateDescription.cloudKitContainerOptions = privateOptions

        let sharedDescription = NSPersistentStoreDescription(url: directory.appendingPathComponent(sharedStoreFileName))
        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudContainerID)
        sharedOptions.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = sharedOptions

        for description in [privateDescription, sharedDescription] {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        return [privateDescription, sharedDescription]
    }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Anniversary", managedObjectModel: ModelSchema.model)

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if !inMemory {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        container.persistentStoreDescriptions = Self.makeStoreDescriptions(inMemory: inMemory, directory: dir)

        var loadError: Error?
        container.loadPersistentStores { _, error in if let error { loadError = error } }
        precondition(loadError == nil, "本地库加载失败: \(String(describing: loadError))")

        let stores = container.persistentStoreCoordinator.persistentStores
        if inMemory {
            privateStore = stores.first
            sharedStore = nil
        } else {
            privateStore = stores.first { $0.url?.lastPathComponent == Self.privateStoreFileName }
            sharedStore = stores.first { $0.url?.lastPathComponent == Self.sharedStoreFileName }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        container.viewContext.transactionAuthor = Self.localTransactionAuthor

        #if DEBUG
        // 一次性动作：Xcode scheme 勾选 -InitCloudKitSchema 跑一次，把 15 个实体的
        // 记录类型全量推到 CloudKit Development 环境（含 P4/P5 未产生数据的实体），
        // 之后在 CloudKit Console 部署到 Production。见 docs/RELEASE.md。
        if ProcessInfo.processInfo.arguments.contains("-InitCloudKitSchema") {
            do {
                try container.initializeCloudKitSchema(options: [])
                print("✅ CloudKit schema 初始化完成（Development 环境）")
            } catch {
                print("❌ CloudKit schema 初始化失败：\(error)")
            }
        }
        #endif
    }
}
