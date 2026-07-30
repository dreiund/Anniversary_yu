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
}
