import XCTest
import UIKit
@testable import Anniversary

final class MomentRepositoryTests: XCTestCase {
    private var pc: PersistenceController!
    private var meetings: MeetingRepository!
    private var moments: MomentRepository!
    private var couple: CDCouple!
    private var meeting: CDMeeting!
    private var creatorID: UUID!

    override func setUpWithError() throws {
        pc = PersistenceController(inMemory: true)
        let couples = CoupleRepository(context: pc.viewContext)
        couple = try couples.bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        creatorID = couples.currentPartnerID(of: couple)
        meetings = MeetingRepository(context: pc.viewContext)
        moments = MomentRepository(context: pc.viewContext)
        meeting = try meetings.createPlanned(couple: couple, title: nil, city: "上海", plannedStart: nil, plannedEnd: nil)
        try meetings.start(meeting, at: Date(timeIntervalSince1970: 0))
    }

    private func imageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 800))
        return renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 800))
        }.jpegData(compressionQuality: 0.9)!
    }

    func testCreateAssignsOpenDayAndStoresPhotoWithThumbnail() throws {
        let data = imageData()
        let m = try moments.create(in: meeting, type: .restaurant, title: "蟹家大院", body: "排队四十分钟",
                                   happenedAt: Date(timeIntervalSince1970: 1_000),
                                   photoDatas: [data],
                                   myEvaluation: NewEvaluation(stars: 5, moodEmoji: "😋", comment: "封神"),
                                   authorID: creatorID, place: nil)

        XCTAssertEqual(m.dateDay?.dayIndex, 1)
        let photos = moments.photosSorted(m)
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos[0].imageData, data)
        XCTAssertNotNil(photos[0].thumbnailData)
        let eval = moments.evaluation(of: m, by: creatorID)
        XCTAssertEqual(eval?.stars, 5)
        XCTAssertEqual(eval?.comment, "封神")
    }

    func testDaysWithMomentsGroupsAndSorts() throws {
        _ = try moments.create(in: meeting, type: .sight, title: "外滩", body: nil,
                               happenedAt: Date(timeIntervalSince1970: 5_000),
                               photoDatas: [], myEvaluation: nil, authorID: creatorID, place: nil)
        _ = try moments.create(in: meeting, type: .restaurant, title: "早茶", body: nil,
                               happenedAt: Date(timeIntervalSince1970: 2_000),
                               photoDatas: [], myEvaluation: nil, authorID: creatorID, place: nil)
        try meetings.sealOpenDay(in: meeting, at: Date(timeIntervalSince1970: 40_000))
        _ = try moments.create(in: meeting, type: .activity, title: "桌游", body: nil,
                               happenedAt: Date(timeIntervalSince1970: 50_000),
                               photoDatas: [], myEvaluation: nil, authorID: creatorID, place: nil)

        let grouped = moments.daysWithMoments(in: meeting)
        XCTAssertEqual(grouped.map(\.day.dayIndex), [1, 2])
        XCTAssertEqual(grouped[0].moments.map(\.title), ["早茶", "外滩"])
        XCTAssertEqual(grouped[1].moments.map(\.title), ["桌游"])
    }

    func testMoveAndDelete() throws {
        let a = try moments.create(in: meeting, type: .other, title: "A", body: nil,
                                   happenedAt: Date(timeIntervalSince1970: 1_000),
                                   photoDatas: [], myEvaluation: nil, authorID: creatorID, place: nil)
        try meetings.sealOpenDay(in: meeting, at: Date(timeIntervalSince1970: 2_000))
        let b = try moments.create(in: meeting, type: .other, title: "B", body: nil,
                                   happenedAt: Date(timeIntervalSince1970: 3_000),
                                   photoDatas: [], myEvaluation: nil, authorID: creatorID, place: nil)
        let day1 = try XCTUnwrap(a.dateDay)

        try moments.move(b, to: day1)
        XCTAssertEqual(moments.daysWithMoments(in: meeting)[0].moments.map(\.title), ["A", "B"])

        try moments.delete(a)
        XCTAssertEqual(moments.daysWithMoments(in: meeting)[0].moments.map(\.title), ["B"])
    }

    func testUpsertEvaluationCreatesThenUpdates() throws {
        let moment = try moments.create(in: meeting, type: .restaurant, title: "小馆子", body: nil,
                                        happenedAt: Date(), photoDatas: [], myEvaluation: nil,
                                        authorID: nil, place: nil)
        let her = UUID()

        let created = try moments.upsertEvaluation(on: moment, by: her,
                                                   NewEvaluation(stars: 4, moodEmoji: "😊", comment: "好吃"))
        XCTAssertEqual(moments.evaluation(of: moment, by: her)?.objectID, created.objectID)
        XCTAssertEqual(created.stars, 4)

        let updated = try moments.upsertEvaluation(on: moment, by: her,
                                                   NewEvaluation(stars: 5, moodEmoji: "🥰", comment: "改口，超好吃"))
        XCTAssertEqual(updated.objectID, created.objectID, "同作者第二次写入必须是更新不是新建")
        XCTAssertEqual(((moment.evaluations as? Set<CDEvaluation>) ?? []).count, 1)
        XCTAssertEqual(moments.evaluation(of: moment, by: her)?.stars, 5)
        XCTAssertEqual(moments.evaluation(of: moment, by: her)?.comment, "改口，超好吃")
    }

    func testEvaluationLookupDeterministicWhenDuplicated() throws {
        let pc = PersistenceController(inMemory: true)
        let ctx = pc.viewContext
        let couple = try CoupleRepository(context: ctx)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        let meetings = MeetingRepository(context: ctx)
        let meeting = try meetings.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        try meetings.start(meeting, at: Date())
        let repo = MomentRepository(context: ctx)
        let moment = try repo.create(in: meeting, type: .restaurant, title: "馆子", body: nil,
                                     happenedAt: Date(), photoDatas: [], myEvaluation: nil,
                                     authorID: nil, place: nil)
        let author = UUID()
        let idA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
        let idB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!
        for (uuid, stars) in [(idB, Int16(2)), (idA, Int16(4))] {
            let ev = CDEvaluation(context: ctx)
            ev.id = uuid
            ev.authorPartnerID = author
            ev.stars = stars
            ev.moment = moment
        }
        try ctx.save()
        let found = repo.evaluation(of: moment, by: author)
        XCTAssertEqual(found?.id, idA, "重复时必须取 id 字典序最小的一条，两端一致")
    }
}
