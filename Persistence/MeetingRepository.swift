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
}
