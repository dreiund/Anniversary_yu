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
        // CloudKit 禁 unique 约束，双端并发下同 (author, day) 可能短暂重复；
        // 按 id 字典序取首条，保证两端渲染选择一致（后写内容仍以字段级合并策略收敛）。
        // 时区：两位使用者均在东八区，startOfDay 以本机时区归一（spec §9 时间条款）。
        return ((couple.dailyMoods as? Set<CDDailyMood>) ?? [])
            .filter { $0.authorPartnerID == authorID && $0.day == normalized }
            .sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
            .first
    }
}
