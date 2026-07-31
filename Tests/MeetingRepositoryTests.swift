import XCTest
@testable import Anniversary

final class MeetingRepositoryTests: XCTestCase {
    private func makeCouple() throws -> (PersistenceController, CDCouple) {
        let pc = PersistenceController(inMemory: true)
        let couple = try CoupleRepository(context: pc.viewContext)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        return (pc, couple)
    }

    func testCreatePlannedAutoIncrementsIndex() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)

        let m1 = try repo.createPlanned(couple: couple, title: nil, city: "上海",
                                        plannedStart: Date(timeIntervalSince1970: 100), plannedEnd: nil)
        let m2 = try repo.createPlanned(couple: couple, title: "秋游", city: "杭州",
                                        plannedStart: Date(timeIntervalSince1970: 200), plannedEnd: nil)

        XCTAssertEqual(m1.index, 1)
        XCTAssertEqual(m2.index, 2)
        XCTAssertEqual(repo.status(of: m1), .planned)
    }

    func testStartAndEndTransitions() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)

        let t1 = Date(timeIntervalSince1970: 1_000)
        try repo.start(m, at: t1)
        XCTAssertEqual(repo.status(of: m), .ongoing)
        XCTAssertEqual(m.startedAt, t1)
        XCTAssertEqual(try repo.ongoingMeeting(couple: couple)?.objectID, m.objectID)

        let t2 = Date(timeIntervalSince1970: 2_000)
        try repo.end(m, at: t2)
        XCTAssertEqual(repo.status(of: m), .finished)
        XCTAssertEqual(m.endedAt, t2)
        XCTAssertNil(try repo.ongoingMeeting(couple: couple))
    }

    func testNextPlannedPicksEarliestUpcoming() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let now = Date(timeIntervalSince1970: 10_000)

        _ = try repo.createPlanned(couple: couple, title: "过去的", city: nil,
                                   plannedStart: now.addingTimeInterval(-86_400), plannedEnd: nil)
        let near = try repo.createPlanned(couple: couple, title: "近", city: nil,
                                          plannedStart: now.addingTimeInterval(86_400), plannedEnd: nil)
        _ = try repo.createPlanned(couple: couple, title: "远", city: nil,
                                   plannedStart: now.addingTimeInterval(10 * 86_400), plannedEnd: nil)

        XCTAssertEqual(try repo.nextPlannedMeeting(couple: couple, after: now)?.objectID, near.objectID)
    }

    func testMeetingsSortedNewestFirst() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        _ = try repo.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        _ = try repo.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)

        XCTAssertEqual(try repo.meetingsSorted(couple: couple).map(\.index), [2, 1])
    }
}
