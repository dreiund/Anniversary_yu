import XCTest
@testable import Anniversary

final class DailyMoodRepositoryTests: XCTestCase {
    func testSetMoodUpsertsPerAuthorPerDay() throws {
        let pc = PersistenceController(inMemory: true)
        let couples = CoupleRepository(context: pc.viewContext)
        let couple = try couples.bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        let me = couples.currentPartnerID(of: couple)
        let repo = DailyMoodRepository(context: pc.viewContext)
        let cal = Calendar(identifier: .gregorian)
        let morning = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 9))!
        let evening = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 21))!

        _ = try repo.setMood(couple: couple, authorID: me, day: morning, emoji: "😊", note: nil, calendar: cal)
        _ = try repo.setMood(couple: couple, authorID: me, day: evening, emoji: "🥰", note: "见面了", calendar: cal)

        let all = (couple.dailyMoods as? Set<CDDailyMood>) ?? []
        XCTAssertEqual(all.count, 1)
        let found = repo.mood(couple: couple, authorID: me, day: evening, calendar: cal)
        XCTAssertEqual(found?.moodEmoji, "🥰")
        XCTAssertEqual(found?.note, "见面了")
    }

    func testMoodLookupDeterministicWhenDuplicated() throws {
        let pc = PersistenceController(inMemory: true)
        let ctx = pc.viewContext
        let couple = try CoupleRepository(context: ctx)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        let author = UUID()
        let day = Calendar.current.startOfDay(for: Date())
        let idA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
        let idB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!
        for (uuid, emoji) in [(idB, "😐"), (idA, "😊")] {
            let mood = CDDailyMood(context: ctx)
            mood.id = uuid
            mood.authorPartnerID = author
            mood.day = day
            mood.moodEmoji = emoji
            mood.couple = couple
        }
        try ctx.save()
        let found = DailyMoodRepository(context: ctx)
            .mood(couple: couple, authorID: author, day: day, calendar: .current)
        XCTAssertEqual(found?.id, idA, "重复时必须取 id 字典序最小的一条，两端一致")
    }
}
