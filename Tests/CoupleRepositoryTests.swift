import XCTest
@testable import Anniversary

final class CoupleRepositoryTests: XCTestCase {
    func testBootstrapCreatesCoupleWithTwoPartners() throws {
        let pc = PersistenceController(inMemory: true)
        let repo = CoupleRepository(context: pc.viewContext)
        let anniversary = Date(timeIntervalSince1970: 1_749_398_400)

        let couple = try repo.bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: anniversary)

        XCTAssertNotNil(couple.id)
        XCTAssertEqual(couple.anniversaryDate, anniversary)
        let partners = repo.partners(of: couple)
        XCTAssertEqual(partners.count, 2)
        XCTAssertEqual(partners[0].name, "阿铖")
        XCTAssertEqual(partners[1].name, "小于")
    }

    func testBootstrapIsIdempotent() throws {
        let pc = PersistenceController(inMemory: true)
        let repo = CoupleRepository(context: pc.viewContext)

        let first = try repo.bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        let second = try repo.bootstrapIfNeeded(myName: "别人", partnerName: "别人2", anniversary: Date())

        XCTAssertEqual(first.objectID, second.objectID)
        let all = try pc.viewContext.fetch(CDCouple.fetchRequest()) as! [CDCouple]
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(repo.partners(of: second).map(\.name), ["阿铖", "小于"])
    }

    func testFetchCoupleReturnsNilBeforeBootstrap() throws {
        let pc = PersistenceController(inMemory: true)
        let repo = CoupleRepository(context: pc.viewContext)
        XCTAssertNil(try repo.fetchCouple())
    }
}
