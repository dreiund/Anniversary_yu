import CoreData

enum PreviewData {
    /// 预览与手动调试用内存栈：一对情侣 + 一次进行中的见面 + 一条已封盘的约会日
    static func makeController() -> PersistenceController {
        let pc = PersistenceController(inMemory: true)
        let ctx = pc.viewContext
        let repo = CoupleRepository(context: ctx)

        do {
            let couple = try repo.bootstrapIfNeeded(
                myName: "阿铖", partnerName: "小于",
                anniversary: Calendar.current.date(byAdding: .day, value: -412, to: Date())
            )

            let meeting = CDMeeting(context: ctx)
            meeting.id = UUID()
            meeting.index = 7
            meeting.city = "上海"
            meeting.statusRaw = MeetingStatus.ongoing.rawValue
            meeting.startedAt = Calendar.current.date(byAdding: .day, value: -1, to: Date())
            meeting.couple = couple

            let day1 = CDDateDay(context: ctx)
            day1.id = UUID()
            day1.dayIndex = 1
            day1.openedAt = meeting.startedAt
            day1.closedAt = Calendar.current.date(byAdding: .hour, value: 12, to: meeting.startedAt!)
            day1.meeting = meeting

            let moment = CDMoment(context: ctx)
            moment.id = UUID()
            moment.title = "蟹家大院"
            moment.typeRaw = MomentType.restaurant.rawValue
            moment.happenedAt = day1.openedAt
            moment.createdAt = day1.openedAt
            moment.dateDay = day1

            let eval = CDEvaluation(context: ctx)
            eval.id = UUID()
            eval.authorPartnerID = repo.partners(of: couple)[0].id
            eval.stars = 5
            eval.moodEmoji = "😋"
            eval.comment = "秃黄油拌饭封神"
            eval.moment = moment

            let plan = CDPlanItem(context: ctx)
            plan.id = UUID()
            plan.title = "G102 高铁"
            plan.isDone = true
            plan.sortIndex = 0
            plan.meeting = meeting

            let meetingRepo = MeetingRepository(context: ctx)
            let planned = try meetingRepo.createPlanned(
                couple: couple, title: "上海行", city: "上海",
                plannedStart: Calendar.current.date(byAdding: .day, value: 12, to: Date()),
                plannedEnd: Calendar.current.date(byAdding: .day, value: 16, to: Date()))

            let planRepo = PlanItemRepository(context: ctx)
            let trainDay = Calendar.current.date(byAdding: .day, value: 12, to: Date())!
            _ = try planRepo.add(to: planned, day: trainDay,
                                 time: Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: trainDay),
                                 title: "G102 高铁", note: "车票已订 · 靠窗",
                                 placeText: nil, authorID: repo.partners(of: couple)[0].id)
            _ = try planRepo.add(to: planned, day: nil, time: nil, title: "带充电宝",
                                 note: nil, placeText: nil, authorID: repo.partners(of: couple)[0].id)

            _ = try DailyMoodRepository(context: ctx).setMood(
                couple: couple, authorID: repo.partners(of: couple)[0].id,
                day: Date(), emoji: "😊", note: nil, calendar: .current)

            try ctx.save()
        } catch {
            assertionFailure("PreviewData 构建失败: \(error)")
        }
        return pc
    }
}
