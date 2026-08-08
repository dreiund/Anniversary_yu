import XCTest
import CoreData
@testable import Anniversary

final class PlacePrunerTests: XCTestCase {
    private var pc: PersistenceController!
    private var couple: CDCouple!

    override func setUpWithError() throws {
        pc = PersistenceController(inMemory: true)
        couple = try CoupleRepository(context: pc.viewContext)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
    }

    private func makePlace(_ name: String) -> CDPlace {
        let place = CDPlace(context: pc.viewContext)
        place.id = UUID()
        place.name = name
        place.latitude = 31.0
        place.longitude = 121.0
        place.couple = couple
        return place
    }

    private func placeCount() throws -> Int {
        try pc.viewContext.fetch(NSFetchRequest<CDPlace>(entityName: "CDPlace")).count
    }

    // 反馈⑥：删光引用记录后地点应随之清除（选点地图不再残留旧钉）
    func testDeletingLastMomentPrunesPlace() throws {
        let meetings = MeetingRepository(context: pc.viewContext)
        let moments = MomentRepository(context: pc.viewContext)
        let m = try meetings.createPlanned(couple: couple, title: nil, city: nil,
                                           plannedStart: nil, plannedEnd: nil)
        try meetings.start(m, at: Date(timeIntervalSince1970: 100))
        let place = makePlace("要清的店")
        let moment = try moments.create(in: m, type: .other, title: "唯一引用", body: nil,
                                        happenedAt: Date(timeIntervalSince1970: 150), photoDatas: [],
                                        myEvaluation: nil, authorID: nil, place: place)
        XCTAssertEqual(try placeCount(), 1)
        try moments.delete(moment)
        XCTAssertEqual(try placeCount(), 0)                        // 孤儿地点已清
    }

    func testPlaceWithRemainingLedgerReferenceSurvives() throws {
        let meetings = MeetingRepository(context: pc.viewContext)
        let moments = MomentRepository(context: pc.viewContext)
        let ledger = LedgerRepository(context: pc.viewContext)
        let m = try meetings.createPlanned(couple: couple, title: nil, city: nil,
                                           plannedStart: nil, plannedEnd: nil)
        try meetings.start(m, at: Date(timeIntervalSince1970: 100))
        let place = makePlace("双引用的店")
        let moment = try moments.create(in: m, type: .other, title: "记忆引用", body: nil,
                                        happenedAt: Date(timeIntervalSince1970: 150), photoDatas: [],
                                        myEvaluation: nil, authorID: nil, place: place)
        let entry = try ledger.createEntry(couple: couple, category: .praise, title: "小本本引用",
                                           detail: nil, happenedAt: Date(timeIntervalSince1970: 160),
                                           visibility: .sharedImmediately, place: place,
                                           evidenceDatas: [], authorID: nil)
        try moments.delete(moment)
        XCTAssertEqual(try placeCount(), 1)                        // 还有小本本引用：保留
        try ledger.delete(entry)
        XCTAssertEqual(try placeCount(), 0)                        // 最后引用没了：清除
    }

    func testMeetingCascadeDeletePrunesPlace() throws {
        let meetings = MeetingRepository(context: pc.viewContext)
        let moments = MomentRepository(context: pc.viewContext)
        let m = try meetings.createPlanned(couple: couple, title: nil, city: nil,
                                           plannedStart: nil, plannedEnd: nil)
        try meetings.start(m, at: Date(timeIntervalSince1970: 100))
        let place = makePlace("随见面走的店")
        _ = try moments.create(in: m, type: .other, title: "级联", body: nil,
                               happenedAt: Date(timeIntervalSince1970: 150), photoDatas: [],
                               myEvaluation: nil, authorID: nil, place: place)
        try meetings.delete(m)                                     // 级联删记忆 → 地点成孤儿
        XCTAssertEqual(try placeCount(), 0)
    }
}
