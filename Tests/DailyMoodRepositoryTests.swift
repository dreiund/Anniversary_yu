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
}
