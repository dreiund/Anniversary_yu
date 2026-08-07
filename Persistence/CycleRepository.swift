import CoreData

/// 周期仓库（spec §二/§四）：所有日期落库前 startOfDay；重叠=区间相交（进行中段上界开放）
struct CycleRepository {
    let context: NSManagedObjectContext

    enum CycleError: Error, Equatable {
        case endBeforeStart
        case overlap(existingStart: Date, existingEnd: Date?)
        case hasOngoing, future
    }

    func cyclesSorted(couple: CDCouple) -> [CDCycle] {
        ((couple.cycles as? Set<CDCycle>) ?? [])
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    func ongoing(couple: CDCouple) -> CDCycle? {
        cyclesSorted(couple: couple).first { $0.endDate == nil }
    }

    func cycle(containing day: Date, couple: CDCouple, calendar: Calendar) -> CDCycle? {
        let target = calendar.startOfDay(for: day)
        return cyclesSorted(couple: couple).first { c in
            guard let start = c.startDate else { return false }
            let upper = c.endDate ?? .distantFuture
            return start <= target && target <= upper
        }
    }

    @discardableResult
    func start(couple: CDCouple, on day: Date, predictedStart: Date?,
               today: Date, calendar: Calendar) throws -> CDCycle {
        let d = calendar.startOfDay(for: day)
        guard d <= calendar.startOfDay(for: today) else { throw CycleError.future }
        guard ongoing(couple: couple) == nil else { throw CycleError.hasOngoing }
        try assertNoOverlap(start: d, end: nil, excluding: nil, couple: couple)
        let cycle = CDCycle(context: context)
        cycle.id = UUID()
        cycle.startDate = d
        cycle.predictedStartAtLogging = predictedStart
        cycle.couple = couple
        try context.save()
        return cycle
    }

    func end(_ cycle: CDCycle, on day: Date, calendar: Calendar) throws {
        let d = calendar.startOfDay(for: day)
        guard let start = cycle.startDate, d >= start else { throw CycleError.endBeforeStart }
        guard let couple = cycle.couple else { return }
        try assertNoOverlap(start: start, end: d, excluding: cycle, couple: couple)
        cycle.endDate = d
        try context.save()
    }

    @discardableResult
    func backfill(couple: CDCouple, start: Date, end: Date,
                  today: Date, calendar: Calendar) throws -> CDCycle {
        let s = calendar.startOfDay(for: start), e = calendar.startOfDay(for: end)
        guard e >= s else { throw CycleError.endBeforeStart }
        let todayStart = calendar.startOfDay(for: today)
        guard s <= todayStart else { throw CycleError.future }
        guard e <= todayStart else { throw CycleError.future }
        try assertNoOverlap(start: s, end: e, excluding: nil, couple: couple)
        let cycle = CDCycle(context: context)
        cycle.id = UUID()
        cycle.startDate = s
        cycle.endDate = e
        cycle.couple = couple                                  // 无当时预测：predictedStartAtLogging 留空
        try context.save()
        return cycle
    }

    func updateRange(_ cycle: CDCycle, start: Date, end: Date?,
                      today: Date = Date(), calendar: Calendar) throws {
        let s = calendar.startOfDay(for: start)
        let e = end.map { calendar.startOfDay(for: $0) }
        if let e, e < s { throw CycleError.endBeforeStart }
        let todayStart = calendar.startOfDay(for: today)
        guard s <= todayStart else { throw CycleError.future }
        if let e { guard e <= todayStart else { throw CycleError.future } }
        guard let couple = cycle.couple else { return }
        try assertNoOverlap(start: s, end: e, excluding: cycle, couple: couple)
        cycle.startDate = s
        cycle.endDate = e
        try context.save()
    }

    func delete(_ cycle: CDCycle) throws {
        context.delete(cycle)                                  // dayLogs 模型级联
        try context.save()
    }

    private func assertNoOverlap(start: Date, end: Date?, excluding: CDCycle?, couple: CDCouple) throws {
        let upper = end ?? .distantFuture
        for other in cyclesSorted(couple: couple) where other.objectID != excluding?.objectID {
            guard let oStart = other.startDate else { continue }
            let oUpper = other.endDate ?? .distantFuture
            if oStart <= upper && start <= oUpper {
                throw CycleError.overlap(existingStart: oStart, existingEnd: other.endDate)
            }
        }
    }

    func dayLog(in cycle: CDCycle, day: Date, calendar: Calendar) -> CDCycleDayLog? {
        let target = calendar.startOfDay(for: day)
        return ((cycle.dayLogs as? Set<CDCycleDayLog>) ?? []).first { $0.day == target }
    }

    /// 每（周期,自然日）至多一条：有则整体覆盖，无则新建（spec §三）
    @discardableResult
    func setDayLog(in cycle: CDCycle, day: Date, painRaw: Int16, flowRaw: Int16,
                   colorRaw: Int16, note: String?, calendar: Calendar) throws -> CDCycleDayLog {
        let log = dayLog(in: cycle, day: day, calendar: calendar) ?? {
            let fresh = CDCycleDayLog(context: context)
            fresh.id = UUID()
            fresh.day = calendar.startOfDay(for: day)
            fresh.cycle = cycle
            return fresh
        }()
        log.painRaw = painRaw
        log.flowRaw = flowRaw
        log.colorRaw = colorRaw
        log.note = note
        try context.save()
        return log
    }
}

extension CycleRepository {
    /// 亲密（spec §二）：今天=now 时刻；过去=当天 12:00；今天且见面进行中挂开着的约会日
    @discardableResult
    func addIntimacy(couple: CDCouple, day: Date, protected: Bool, note: String?,
                     now: Date, calendar: Calendar) throws -> CDIntimacyRecord {
        let record = CDIntimacyRecord(context: context)
        record.id = UUID()
        record.protectionUsed = NSNumber(value: protected)
        record.note = note
        record.couple = couple
        if calendar.isDate(day, inSameDayAs: now) {
            record.happenedAt = now
            if let meeting = try? MeetingRepository(context: context).ongoingMeeting(couple: couple),
               let open = try? MeetingRepository(context: context).openDay(in: meeting) {
                record.dateDay = open
            }
        } else {
            record.happenedAt = calendar.date(bySettingHour: 12, minute: 0, second: 0,
                                              of: calendar.startOfDay(for: day))
        }
        try context.save()
        return record
    }

    func intimacy(on day: Date, couple: CDCouple, calendar: Calendar) -> [CDIntimacyRecord] {
        ((couple.intimacyRecords as? Set<CDIntimacyRecord>) ?? [])
            .filter { $0.happenedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { ($0.happenedAt ?? .distantPast) < ($1.happenedAt ?? .distantPast) }
    }

    func updateIntimacy(_ record: CDIntimacyRecord, protected: Bool, note: String?) throws {
        record.protectionUsed = NSNumber(value: protected)
        record.note = note
        try context.save()
    }

    func deleteIntimacy(_ record: CDIntimacyRecord) throws {
        context.delete(record)
        try context.save()
    }

    /// 归属（spec §七）：独占单选；改归属不动周期数据
    func trackedPartner(couple: CDCouple) -> CDPartner? {
        CoupleRepository(context: context).partners(of: couple).first(where: \.tracksCycle)
    }

    func setTracked(_ partner: CDPartner, couple: CDCouple) throws {
        for p in CoupleRepository(context: context).partners(of: couple) {
            p.tracksCycle = (p.objectID == partner.objectID)
        }
        try context.save()
    }
}
