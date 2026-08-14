import XCTest
import CoreData
@testable import Anniversary

final class MeetingPrivacyTests: XCTestCase {
    var container: NSPersistentContainer!
    var context: NSManagedObjectContext { container.viewContext }

    override func setUp() {
        super.setUp()
        container = NSPersistentContainer(name: "Test", managedObjectModel: ModelSchema.model)
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores { _, _ in }
    }

    private func makeCouple() throws -> CDCouple {
        try CoupleRepository(context: context)
            .bootstrapIfNeeded(myName: "我", partnerName: "TA", anniversary: nil)
    }

    func testCreatePlannedDefaultsArePublicAndAuthorless() throws {
        let couple = try makeCouple()
        let m = try MeetingRepository(context: context).createPlanned(
            couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        XCTAssertNil(m.authorPartnerID)
        XCTAssertEqual(m.visibilityRaw, EntryVisibility.sharedImmediately.rawValue)
        XCTAssertNil(m.revealedAt)
    }

    func testCreatePlannedPrivateCarriesAuthorAndVisibility() throws {
        let couple = try makeCouple()
        let myID = CoupleRepository(context: context).currentPartnerID(of: couple)
        let m = try MeetingRepository(context: context).createPlanned(
            couple: couple, title: "惊喜", city: nil, plannedStart: nil, plannedEnd: nil,
            authorID: myID, visibility: .privateUntilRevealed)
        XCTAssertEqual(m.authorPartnerID, myID)
        XCTAssertEqual(m.visibilityRaw, EntryVisibility.privateUntilRevealed.rawValue)
    }

    func testRevealIsIdempotent() throws {
        let couple = try makeCouple()
        let repo = MeetingRepository(context: context)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil,
                                       plannedStart: nil, plannedEnd: nil,
                                       authorID: nil, visibility: .privateUntilRevealed)
        let t1 = Date(timeIntervalSince1970: 100)
        try repo.reveal(m, at: t1)
        XCTAssertEqual(m.revealedAt, t1)
        try repo.reveal(m, at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(m.revealedAt, t1)   // 时戳留痕,不可覆盖
    }

    func testStartAutoRevealsPrivateMeeting() throws {
        let couple = try makeCouple()
        let repo = MeetingRepository(context: context)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil,
                                       plannedStart: nil, plannedEnd: nil,
                                       authorID: nil, visibility: .privateUntilRevealed)
        let start = Date(timeIntervalSince1970: 500)
        try repo.start(m, at: start)
        XCTAssertEqual(m.revealedAt, start)   // 开始见面=自动公开(spec §四)
        XCTAssertEqual(m.statusRaw, MeetingStatus.ongoing.rawValue)
    }

    func testStartDoesNotStampRevealOnPublicMeeting() throws {
        let couple = try makeCouple()
        let repo = MeetingRepository(context: context)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil,
                                       plannedStart: nil, plannedEnd: nil)
        try repo.start(m, at: Date())
        XCTAssertNil(m.revealedAt)   // 公开见面不需要公开时戳
    }

    /// 可见性判定表:meeting 口径直接复用 LedgerRules.isVisible(spec §四)
    func testVisibilityTable() {
        let me = UUID(), other = UUID()
        let priv = EntryVisibility.privateUntilRevealed.rawValue
        let pub = EntryVisibility.sharedImmediately.rawValue
        // 作者自己恒可见
        XCTAssertTrue(LedgerRules.isVisible(authorID: me, myID: me, visibilityRaw: priv, revealedAt: nil))
        // 对方的私密未公开不可见
        XCTAssertFalse(LedgerRules.isVisible(authorID: other, myID: me, visibilityRaw: priv, revealedAt: nil))
        // 公开后可见
        XCTAssertTrue(LedgerRules.isVisible(authorID: other, myID: me, visibilityRaw: priv, revealedAt: Date()))
        // 旧数据 nil 作者 + raw 0 = 双方可见
        XCTAssertTrue(LedgerRules.isVisible(authorID: nil, myID: me, visibilityRaw: pub, revealedAt: nil))
    }
}
