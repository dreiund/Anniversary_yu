import CoreData

struct DailyMoodRepository {
    let context: NSManagedObjectContext

    @discardableResult
    func setMood(couple: CDCouple, authorID: UUID?, day: Date, emoji: String,
                 note: String?, calendar: Calendar) throws -> CDDailyMood {
        let normalized = calendar.startOfDay(for: day)
        let mood: CDDailyMood
        if let existing = self.mood(couple: couple, authorID: authorID, day: day, calendar: calendar) {
            mood = existing
        } else {
            mood = CDDailyMood(context: context)
            mood.id = UUID()
            mood.authorPartnerID = authorID
            mood.day = normalized
            mood.couple = couple
        }
        mood.moodEmoji = emoji
        mood.note = note
        try context.save()
        return mood
    }

    func mood(couple: CDCouple, authorID: UUID?, day: Date, calendar: Calendar) -> CDDailyMood? {
        let normalized = calendar.startOfDay(for: day)
        return ((couple.dailyMoods as? Set<CDDailyMood>) ?? [])
            .first { $0.authorPartnerID == authorID && $0.day == normalized }
    }
}
