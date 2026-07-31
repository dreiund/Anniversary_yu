import CoreData

struct MeetingRepository {
    let context: NSManagedObjectContext

    func status(of meeting: CDMeeting) -> MeetingStatus {
        MeetingStatus(rawValue: meeting.statusRaw) ?? .planned
    }

    @discardableResult
    func createPlanned(couple: CDCouple, title: String?, city: String?,
                       plannedStart: Date?, plannedEnd: Date?) throws -> CDMeeting {
        let maxIndex = ((couple.meetings as? Set<CDMeeting>) ?? [])
            .map(\.index).max() ?? 0
        let meeting = CDMeeting(context: context)
        meeting.id = UUID()
        meeting.index = maxIndex + 1
        meeting.title = title
        meeting.city = city
        meeting.plannedStart = plannedStart
        meeting.plannedEnd = plannedEnd
        meeting.statusRaw = MeetingStatus.planned.rawValue
        meeting.couple = couple
        try context.save()
        return meeting
    }

    func start(_ meeting: CDMeeting, at date: Date) throws {
        meeting.statusRaw = MeetingStatus.ongoing.rawValue
        meeting.startedAt = date
        try context.save()
    }

    func end(_ meeting: CDMeeting, at date: Date) throws {
        try sealOpenDay(in: meeting, at: date)
        meeting.statusRaw = MeetingStatus.finished.rawValue
        meeting.endedAt = date
        try context.save()
    }

    func ongoingMeeting(couple: CDCouple) throws -> CDMeeting? {
        ((couple.meetings as? Set<CDMeeting>) ?? [])
            .first { $0.statusRaw == MeetingStatus.ongoing.rawValue }
    }

    func nextPlannedMeeting(couple: CDCouple, after date: Date) throws -> CDMeeting? {
        ((couple.meetings as? Set<CDMeeting>) ?? [])
            .filter { $0.statusRaw == MeetingStatus.planned.rawValue }
            .filter { ($0.plannedStart ?? .distantFuture) >= date }
            .min { ($0.plannedStart ?? .distantFuture) < ($1.plannedStart ?? .distantFuture) }
    }

    func meetingsSorted(couple: CDCouple) throws -> [CDMeeting] {
        ((couple.meetings as? Set<CDMeeting>) ?? [])
            .sorted { $0.index > $1.index }
    }
}

extension MeetingRepository {
    /// 封掉当前开着的约会日（无开着的天则为 no-op）。完整状态机见约会日扩展。
    func sealOpenDay(in meeting: CDMeeting, at date: Date) throws {
        guard let day = try openDay(in: meeting) else { return }
        day.closedAt = date
        try context.save()
    }

    /// 当前开着的约会日：closedAt == nil 中 dayIndex 最大者
    func openDay(in meeting: CDMeeting) throws -> CDDateDay? {
        ((meeting.dateDays as? Set<CDDateDay>) ?? [])
            .filter { $0.closedAt == nil }
            .max { $0.dayIndex < $1.dayIndex }
    }

    /// 新记录归属的约会日：有开着的天用之；否则新开 dayIndex = 已有最大值 + 1（首条即第 1 天）
    @discardableResult
    func dayForNewRecord(in meeting: CDMeeting, at date: Date) throws -> CDDateDay {
        if let open = try openDay(in: meeting) { return open }
        let maxIndex = ((meeting.dateDays as? Set<CDDateDay>) ?? [])
            .map(\.dayIndex).max() ?? 0
        let day = CDDateDay(context: context)
        day.id = UUID()
        day.dayIndex = maxIndex + 1
        day.openedAt = date
        day.meeting = meeting
        try context.save()
        return day
    }

    /// 开着的约会日已超过阈值（默认 18 小时）未封盘 → 返回该天（用于新建记录前的补封拦截）
    func staleOpenDay(in meeting: CDMeeting, now: Date,
                      threshold: TimeInterval = 18 * 3600) throws -> CDDateDay? {
        guard let open = try openDay(in: meeting),
              let openedAt = open.openedAt,
              now.timeIntervalSince(openedAt) > threshold else { return nil }
        return open
    }

    func daysSorted(in meeting: CDMeeting) throws -> [CDDateDay] {
        ((meeting.dateDays as? Set<CDDateDay>) ?? [])
            .sorted { $0.dayIndex < $1.dayIndex }
    }
}
