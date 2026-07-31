import XCTest
import CoreData
@testable import Anniversary

final class CurrentPartnerTests: XCTestCase {
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

    private func makeCouple(in store: NSPersistentStore) throws -> CDCouple {
        let context = container.viewContext
        let couple = CDCouple(context: context)
        couple.id = UUID(); couple.createdAt = Date()
        let me = CDPartner(context: context)
        me.id = UUID(); me.name = "阿铖"; me.roleIndex = 0; me.couple = couple
        let her = CDPartner(context: context)
        her.id = UUID(); her.name = "小于"; her.roleIndex = 1; her.couple = couple
        for object in [couple, me, her] as [NSManagedObject] { context.assign(object, to: store) }
        try context.save()
        return couple
    }

    func testOwnerDeviceResolvesToRoleZero() throws {
        let couple = try makeCouple(in: privateStore)
        let repo = CoupleRepository(context: container.viewContext)
        XCTAssertFalse(repo.isParticipantDevice(couple))
        XCTAssertEqual(repo.currentPartner(of: couple)?.roleIndex, 0)
        XCTAssertEqual(repo.otherPartner(of: couple)?.roleIndex, 1)
        XCTAssertEqual(repo.currentPartnerID(of: couple), repo.partners(of: couple)[0].id)
    }

    func testParticipantDeviceResolvesToRoleOne() throws {
        let couple = try makeCouple(in: sharedStore)
        let repo = CoupleRepository(context: container.viewContext)
        XCTAssertTrue(repo.isParticipantDevice(couple))
        XCTAssertEqual(repo.currentPartner(of: couple)?.roleIndex, 1)
        XCTAssertEqual(repo.otherPartner(of: couple)?.roleIndex, 0)
        XCTAssertEqual(repo.currentPartnerID(of: couple), repo.partners(of: couple)[1].id)
    }
}
