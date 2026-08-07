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

    /// 记录归属的约会日（反馈③轮区间规则，spec §5.1 修订 6）：
    /// 1) 时刻落在某天区间 [openedAt, closedAt]（开着的天上界开放）→ 归它，已封的天照收（补录不解封）；
    ///    区间重叠时归 openedAt 最晚的命中天
    /// 2) 区间外 → 新开一天（openedAt = 记录时刻）；过去的天自动以当日 23:59 收尾——仅区间上界占位，
    ///    不改变"现记睡觉才算结束"的语义（现记的天照旧手动封盘）
    /// 3) 天序号按 openedAt 重排，第 1 天恒为最早
    @discardableResult
    func dayForRecord(in meeting: CDMeeting, at date: Date,
                      now: Date = Date(), calendar: Calendar = .current,
                      sealNewPastDayAt: Date? = nil) throws -> CDDateDay {
        if let hit = rangeHit(in: meeting, at: date) { return hit }
        let day = CDDateDay(context: context)
        day.id = UUID()
        day.openedAt = date
        day.meeting = meeting
        if !calendar.isDate(date, inSameDayAs: now) {
            // 反馈④：补录新开的过去天，收尾时刻优先用调用方（UI 选时刻 sheet）给的；无则 23:59 占位
            day.closedAt = sealNewPastDayAt
                ?? calendar.date(bySettingHour: 23, minute: 59, second: 0, of: date)
        }
        renumberDays(in: meeting)
        try context.save()
        return day
    }

    /// 区间命中：[openedAt, closedAt]（开着的天上界开放），重叠取 openedAt 最晚
    private func rangeHit(in meeting: CDMeeting, at date: Date) -> CDDateDay? {
        ((meeting.dateDays as? Set<CDDateDay>) ?? [])
            .filter { d in
                guard let opened = d.openedAt, opened <= date else { return false }
                guard let closed = d.closedAt else { return true }
                return date <= closed
            }
            .max { ($0.openedAt ?? .distantPast) < ($1.openedAt ?? .distantPast) }
    }

    /// 这条记录会不会新开一个「过去的天」（UI 据此决定是否弹封盘时刻选择）
    func wouldOpenNewPastDay(in meeting: CDMeeting, at date: Date,
                             now: Date = Date(), calendar: Calendar = .current) -> Bool {
        rangeHit(in: meeting, at: date) == nil && !calendar.isDate(date, inSameDayAs: now)
    }

    /// 按 openedAt 时间顺序重编 dayIndex（第 1 天恒为最早；先例：deletePlanned 的序号重排）
    func renumberDays(in meeting: CDMeeting) {
        let sorted = ((meeting.dateDays as? Set<CDDateDay>) ?? [])
            .filter { !$0.isDeleted }   // deleteDay 删后立即重排，关系集里可能还挂着已删对象
            .sorted { ($0.openedAt ?? .distantPast) < ($1.openedAt ?? .distantPast) }
        for (i, day) in sorted.enumerated() where day.dayIndex != Int32(i + 1) {
            day.dayIndex = Int32(i + 1)
        }
    }

    /// 记录挪走后清理空天（无记忆且无亲密记录），并重排天序。调用方随后统一 save。
    func pruneDayIfEmpty(_ day: CDDateDay, in meeting: CDMeeting) {
        let moments = (day.moments as? Set<CDMoment>) ?? []
        let intimacy = (day.intimacyRecords as? Set<CDIntimacyRecord>) ?? []
        guard moments.isEmpty, intimacy.isEmpty else { return }
        context.delete(day)
        renumberDays(in: meeting)
    }

    /// 补封拦截（spec §5.1-4，修订 6 限定）：仅「现记跨天」触发——
    /// 记录的是"今天"的事、开着的天却是更早的自然日、且已开超过阈值。补录过去日期不拦。
    func staleOpenDay(in meeting: CDMeeting, now: Date, recordAt: Date,
                      threshold: TimeInterval = 18 * 3600,
                      calendar: Calendar = .current) throws -> CDDateDay? {
        guard let open = try openDay(in: meeting),
              let openedAt = open.openedAt,
              now.timeIntervalSince(openedAt) > threshold,
              calendar.isDate(recordAt, inSameDayAs: now),
              !calendar.isDate(openedAt, inSameDayAs: recordAt) else { return nil }
        return open
    }

    func daysSorted(in meeting: CDMeeting) throws -> [CDDateDay] {
        ((meeting.dateDays as? Set<CDDateDay>) ?? [])
            .sorted { $0.dayIndex < $1.dayIndex }
    }
}

extension MeetingRepository {
    enum EditError: Error { case notPlanned, dayNotEmpty }

    /// 三态可改基本信息：日期按状态落位（planned→计划日期对；ongoing→仅 startedAt；finished→startedAt+endedAt）
    func update(_ meeting: CDMeeting, title: String?, city: String?,
                start: Date?, end: Date?) throws {
        meeting.title = title
        meeting.city = city
        switch status(of: meeting) {
        case .planned:
            meeting.plannedStart = start
            meeting.plannedEnd = end
        case .ongoing:
            meeting.startedAt = start ?? meeting.startedAt
        case .finished:
            meeting.startedAt = start ?? meeting.startedAt
            meeting.endedAt = end ?? meeting.endedAt
        }
        try context.save()
    }

    /// 任意状态删除（足迹列表左滑）：约会日/记忆/照片/评价/行前日程随模型级联规则一并删除
    /// （亲密记录只解挂归 couple 保留）；其后所有见面序号前移保持连续。
    func delete(_ meeting: CDMeeting) throws {
        try delete([meeting])
    }

    /// 批量删除（管理模式多选）：一次删完统一重排序号、单次保存
    func delete(_ meetings: [CDMeeting]) throws {
        guard let couple = meetings.first?.couple else { return }
        meetings.forEach(context.delete)
        renumberMeetings(in: couple)
        try context.save()
    }

    /// 按既有 index 顺序重编 1..n（与 renumberDays 同构）
    private func renumberMeetings(in couple: CDCouple) {
        ((couple.meetings as? Set<CDMeeting>) ?? [])
            .filter { !$0.isDeleted }
            .sorted { $0.index < $1.index }
            .enumerated()
            .forEach { i, m in
                if m.index != Int32(i + 1) { m.index = Int32(i + 1) }
            }
    }

    /// 仅计划中可删的守卫入口（见面表单的「删除这次计划」沿用）
    func deletePlanned(_ meeting: CDMeeting) throws {
        guard status(of: meeting) == .planned else { throw EditError.notPlanned }
        try delete(meeting)
    }

    /// 删除约会日（时间线左滑封盘卡）：仅空天可删——还有记忆时抛错，由 UI 弹「先删记忆」提示；
    /// 亲密记录随模型规则解挂保留。删后天序号前移保持连续。
    func deleteDay(_ day: CDDateDay) throws {
        guard ((day.moments as? Set<CDMoment>) ?? []).isEmpty else { throw EditError.dayNotEmpty }
        guard let meeting = day.meeting else { return }
        context.delete(day)
        renumberDays(in: meeting)
        try context.save()
    }
}
