import CoreData

struct PlanSections {
    let dated: [(day: Date, items: [CDPlanItem])]
    let undated: [CDPlanItem]
}

struct PlanItemRepository {
    let context: NSManagedObjectContext

    @discardableResult
    func add(to meeting: CDMeeting, day: Date?, time: Date?, title: String,
             note: String?, placeText: String?, authorID: UUID?, remindAt: Date? = nil,
             place: CDPlace? = nil) throws -> CDPlanItem {
        let maxSort = ((meeting.planItems as? Set<CDPlanItem>) ?? [])
            .map(\.sortIndex).max() ?? -1
        let item = CDPlanItem(context: context)
        item.id = UUID()
        item.day = day
        item.time = time
        item.title = title
        item.note = note
        item.placeText = placeText
        item.authorPartnerID = authorID
        item.remindAt = remindAt
        item.sortIndex = maxSort + 1
        item.place = place
        item.meeting = meeting
        try context.save()
        return item
    }

    func toggleDone(_ item: CDPlanItem) throws {
        item.isDone.toggle()
        try context.save()
    }

    func update(_ item: CDPlanItem, day: Date?, time: Date?, title: String,
                note: String?, placeText: String?, remindAt: Date?, place: CDPlace?) throws {
        item.day = day
        item.time = time
        item.title = title
        item.note = note
        item.placeText = placeText
        item.remindAt = remindAt
        item.place = place
        try context.save()
    }

    func delete(_ item: CDPlanItem) throws {
        context.delete(item)
        try context.save()
    }

    /// 批量删除（管理模式多选）：单次保存
    func delete(_ items: [CDPlanItem]) throws {
        items.forEach(context.delete)
        try context.save()
    }

    /// 排序规则（spec §6，测试锁死）：日期升序；同日内先全天（time==nil）后按时间升序，再 sortIndex；无日期归备忘区按 sortIndex
    func sections(for meeting: CDMeeting, calendar: Calendar) -> PlanSections {
        let all = ((meeting.planItems as? Set<CDPlanItem>) ?? [])
        let undated = all.filter { $0.day == nil }
            .sorted { $0.sortIndex < $1.sortIndex }

        let datedItems = all.filter { $0.day != nil }
        let groups = Dictionary(grouping: datedItems) { calendar.startOfDay(for: $0.day!) }
        let dated = groups.keys.sorted().map { key -> (day: Date, items: [CDPlanItem]) in
            let items = groups[key]!.sorted { a, b in
                switch (a.time, b.time) {
                case (nil, nil): return a.sortIndex < b.sortIndex
                case (nil, _): return true
                case (_, nil): return false
                case let (ta?, tb?):
                    // 反馈⑩bug1:只比时分——旧数据(反馈⑧前的独立时间选择器)time 的年月日是「保存当天」,
                    // 跨天保存的两条直接比完整 Date 会乱序;新数据 day=time 同值不受影响
                    let ca = calendar.dateComponents([.hour, .minute], from: ta)
                    let cb = calendar.dateComponents([.hour, .minute], from: tb)
                    let ma = (ca.hour ?? 0) * 60 + (ca.minute ?? 0)
                    let mb = (cb.hour ?? 0) * 60 + (cb.minute ?? 0)
                    return ma != mb ? ma < mb : a.sortIndex < b.sortIndex
                }
            }
            return (key, items)
        }
        return PlanSections(dated: dated, undated: undated)
    }

    func stats(for meeting: CDMeeting) -> (planned: Int, done: Int) {
        let all = ((meeting.planItems as? Set<CDPlanItem>) ?? [])
        return (all.count, all.filter(\.isDone).count)
    }

    /// 计划时刻合成:有时间用日期的年月日+时间的时分;全天用当日 00:00;无日期(备忘)nil
    func plannedMoment(of item: CDPlanItem, calendar: Calendar = .current) -> Date? {
        guard let day = item.day else { return nil }
        guard let time = item.time else { return calendar.startOfDay(for: day) }
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        let t = calendar.dateComponents([.hour, .minute], from: time)
        comps.hour = t.hour
        comps.minute = t.minute
        return calendar.date(from: comps) ?? day
    }

}
