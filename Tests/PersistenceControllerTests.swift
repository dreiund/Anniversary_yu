import XCTest
import CoreData
@testable import Anniversary

final class PersistenceControllerTests: XCTestCase {
    func testInMemoryStackLoadsAndSaves() throws {
        let pc = PersistenceController(inMemory: true)
        XCTAssertEqual(pc.container.persistentStoreCoordinator.persistentStores.count, 1)

        let ctx = pc.viewContext
        let couple = CDCouple(context: ctx)
        couple.id = UUID()
        couple.createdAt = Date()
        try ctx.save()

        let fetched = try ctx.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(fetched.count, 1)
    }

    func testMergePolicyIsPropertyObjectTrump() {
        let pc = PersistenceController(inMemory: true)
        XCTAssertTrue((pc.viewContext.mergePolicy as? NSMergePolicy) === NSMergePolicy.mergeByPropertyObjectTrump)
    }

    func testPersistentHistoryTrackingEnabled() {
        let pc = PersistenceController(inMemory: true)
        let opt = pc.container.persistentStoreDescriptions.first?.options[NSPersistentHistoryTrackingKey] as? NSNumber
        XCTAssertEqual(opt, true)
    }

    func testDiskDescriptionsHavePrivateAndSharedScopes() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let descs = PersistenceController.makeStoreDescriptions(inMemory: false, directory: dir)
        XCTAssertEqual(descs.count, 2)
        XCTAssertEqual(descs[0].url?.lastPathComponent, "Anniversary.sqlite")
        XCTAssertEqual(descs[0].cloudKitContainerOptions?.containerIdentifier, "iCloud.com.fkc.anniversary")
        XCTAssertEqual(descs[0].cloudKitContainerOptions?.databaseScope, .private)
        XCTAssertEqual(descs[1].url?.lastPathComponent, "Anniversary-shared.sqlite")
        XCTAssertEqual(descs[1].cloudKitContainerOptions?.containerIdentifier, "iCloud.com.fkc.anniversary")
        XCTAssertEqual(descs[1].cloudKitContainerOptions?.databaseScope, .shared)
        for d in descs {
            XCTAssertEqual(d.options[NSPersistentHistoryTrackingKey] as? NSNumber, true)
            XCTAssertEqual(d.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber, true)
        }
    }

    func testInMemoryKeepsSingleLocalStoreAndAuthor() {
        let descs = PersistenceController.makeStoreDescriptions(
            inMemory: true, directory: URL(fileURLWithPath: NSTemporaryDirectory()))
        XCTAssertEqual(descs.count, 1)
        XCTAssertNil(descs[0].cloudKitContainerOptions)
        let pc = PersistenceController(inMemory: true)
        XCTAssertNotNil(pc.privateStore)
        XCTAssertNil(pc.sharedStore)
        XCTAssertEqual(pc.viewContext.transactionAuthor, "AnniversaryApp")
    }
}
