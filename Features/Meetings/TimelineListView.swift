import SwiftUI
import CoreData

/// 反馈⑧:daySection 混排记忆与计划的合成条目——放文件私有作用域
/// (嵌套在 @ViewBuilder 函数体内声明会编译报错,故提到文件顶层)
private enum Entry {
    case moment(CDMoment)
    case plan(CDPlanItem)
}

struct TimelineListView: View {
    @Environment(\.managedObjectContext) private var context
    let meeting: CDMeeting
    let selecting: Bool
    @Binding var selected: Set<NSManagedObjectID>
    @FetchRequest private var momentsFetch: FetchedResults<CDMoment>
    @FetchRequest private var daysFetch: FetchedResults<CDDateDay>
    @FetchRequest private var evalsFetch: FetchedResults<CDEvaluation>
    @FetchRequest private var plansFetch: FetchedResults<CDPlanItem>
    @State private var showSeal = false
    @State private var openSwipeID: NSManagedObjectID?
    @State private var pendingDeleteMoment: CDMoment?
    @State private var pendingDeleteDay: CDDateDay?
    @State private var blockedDayCount: Int?
    @State private var showAddPlan = false
    @State private var editingPlan: CDPlanItem?
    @State private var pendingDeletePlan: CDPlanItem?
    @State private var miniMapPlace: CDPlace?

    init(meeting: CDMeeting, selecting: Bool = false,
         selected: Binding<Set<NSManagedObjectID>> = .constant([])) {
        self.meeting = meeting
        self.selecting = selecting
        _selected = selected
        _momentsFetch = FetchRequest(sortDescriptors: [],
                                     predicate: NSPredicate(format: "dateDay.meeting == %@", meeting))
        _daysFetch = FetchRequest(sortDescriptors: [],
                                  predicate: NSPredicate(format: "meeting == %@", meeting))
        _evalsFetch = FetchRequest(sortDescriptors: [],
                                   predicate: NSPredicate(format: "moment.dateDay.meeting == %@", meeting))
        _plansFetch = FetchRequest(sortDescriptors: [],
                                   predicate: NSPredicate(format: "meeting == %@", meeting))
    }

    var body: some View {
        // 注册观察：记忆/约会日（封盘）/评价（含对方补评与修改）/计划项变更均刷新时间线
        let _ = (momentsFetch.count, daysFetch.count, evalsFetch.count, plansFetch.count)
        let momentsRepo = MomentRepository(context: context)
        let grouped = momentsRepo.daysWithMoments(in: meeting)

        // 反馈⑧:计划整体并入时间线——仅进行中/已结束;计划中仍走「计划」chip 的 PlanView,时间线不出计划卡
        let planRepo = PlanItemRepository(context: context)
        let isOngoing = meeting.statusRaw == MeetingStatus.ongoing.rawValue
        let isFinished = meeting.statusRaw == MeetingStatus.finished.rawValue
        let showPlans = isOngoing || isFinished
        let allPlans = showPlans ? Array(plansFetch) : []
        let prepared = allPlans.filter(\.isDone).sorted { $0.sortIndex < $1.sortIndex }
        let pendingPlans = allPlans.filter { !$0.isDone }
        // 散插:时刻落在某个已有天的自然日内 → 进那天;其余(未来/备忘)→ 尾组
        // 注:body 受 @ViewBuilder 约束,块内不能出现 func/type 声明语句(仅 let 可以)——
        // 故用 let 绑定闭包而非嵌套 func(嵌套 func 会报 "closure containing a declaration
        // cannot be used with result builder 'ViewBuilder'")
        let calendar = Calendar.current
        let dayDates = grouped.compactMap { $0.day.openedAt }
        let belongsToExistingDay: (CDPlanItem) -> Bool = { item in
            guard let moment = planRepo.plannedMoment(of: item) else { return false }
            return dayDates.contains { calendar.isDate($0, inSameDayAs: moment) }
        }
        let inserted = pendingPlans.filter(belongsToExistingDay)
        let tail = pendingPlans.filter { !belongsToExistingDay($0) }
            .sorted { a, b in
                let da = planRepo.plannedMoment(of: a) ?? .distantFuture
                let db = planRepo.plannedMoment(of: b) ?? .distantFuture
                return da != db ? da < db : a.sortIndex < b.sortIndex
            }

        LazyVStack(alignment: .leading, spacing: DS.Spacing.md) {
            if grouped.isEmpty && prepared.isEmpty && pendingPlans.isEmpty {
                Text("还没有记录 · 点底栏 ⊕ 记下第一条")
                    .dsCaption()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            }
            if !prepared.isEmpty {
                Text("行前已备 · \(prepared.count)").dsFootnote()
                ForEach(prepared, id: \.objectID) { item in
                    planRow(item, state: .prepared)
                }
            }
            ForEach(grouped, id: \.day.objectID) { day, moments in
                daySection(day: day, moments: moments,
                           plans: inserted.filter { plan in
                               guard let m = planRepo.plannedMoment(of: plan),
                                     let opened = day.openedAt else { return false }
                               return calendar.isDate(m, inSameDayAs: opened)
                           },
                           repo: momentsRepo, planRepo: planRepo)
            }
            if !tail.isEmpty || isOngoing {
                if !tail.isEmpty {
                    Text(isFinished ? "没做成的计划" : "接下来 · 还没做").dsFootnote()
                    ForEach(tail, id: \.objectID) { item in
                        planRow(item, state: isFinished ? .missed : .todo)
                    }
                }
                if isOngoing {
                    Button("＋ 加个待办") { showAddPlan = true }
                        .font(.system(size: 14))
                        .foregroundStyle(DS.actionBlue)
                }
            }
        }
        .sheet(isPresented: $showSeal) { SealSheet(meeting: meeting) }
        .sheet(isPresented: $showAddPlan) { PlanItemFormSheet(meeting: meeting, item: nil) }
        .sheet(item: $editingPlan) { MomentFormView(mode: .fromPlan($0)) }
        .sheet(item: $miniMapPlace) { PlaceMiniMapSheet(place: $0) }
        .alert("删除这条记忆？", isPresented: Binding(get: { pendingDeleteMoment != nil },
                                                set: { if !$0 { pendingDeleteMoment = nil } })) {
            Button("删除记忆", role: .destructive) {
                if let moment = pendingDeleteMoment {
                    try? MomentRepository(context: context).delete(moment)
                }
                pendingDeleteMoment = nil
            }
            Button("取消", role: .cancel) { pendingDeleteMoment = nil }
        } message: {
            Text("这条记忆和它的照片、评价会一并删除，无法恢复。")
        }
        .alert("删除第 \(pendingDeleteDay?.dayIndex ?? 0) 天？",
               isPresented: Binding(get: { pendingDeleteDay != nil },
                                    set: { if !$0 { pendingDeleteDay = nil } })) {
            Button("删除这天", role: .destructive) {
                if let day = pendingDeleteDay {
                    try? MeetingRepository(context: context).deleteDay(day)
                }
                pendingDeleteDay = nil
            }
            Button("取消", role: .cancel) { pendingDeleteDay = nil }
        } message: {
            Text("这一天的封盘记录会删除，之后的天序号自动前移。")
        }
        .alert("还不能删除", isPresented: Binding(get: { blockedDayCount != nil },
                                            set: { if !$0 { blockedDayCount = nil } })) {
            Button("好") { blockedDayCount = nil }
        } message: {
            Text("这一天还有 \(blockedDayCount ?? 0) 条记忆，先删掉记忆再删封盘。")
        }
        .alert("删除这条计划？", isPresented: Binding(get: { pendingDeletePlan != nil },
                                                 set: { if !$0 { pendingDeletePlan = nil } })) {
            Button("删除计划", role: .destructive) {
                if let item = pendingDeletePlan {
                    if let id = item.id { ReminderScheduler.cancelPlans([id]) }
                    try? PlanItemRepository(context: context).delete(item)
                }
                pendingDeletePlan = nil
            }
            Button("取消", role: .cancel) { pendingDeletePlan = nil }
        } message: {
            Text("只删这条计划，不影响任何记忆。")
        }
    }

    @ViewBuilder
    private func daySection(day: CDDateDay, moments: [CDMoment], plans: [CDPlanItem],
                             repo: MomentRepository, planRepo: PlanItemRepository) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("第 \(day.dayIndex) 天").dsPageTitle()
            if let opened = day.openedAt {
                Text("\(Fmt.monthDayWeek.string(from: opened)) · \(Fmt.hm.string(from: opened)) 出门").dsFootnote()
            }
        }
        // 混排:回忆按 happenedAt、计划按合成时刻(全天=00:00 排组首)
        let entries: [(key: String, at: Date, entry: Entry)] =
            moments.map { ("m-\($0.objectID)", $0.happenedAt ?? .distantPast, .moment($0)) }
            + plans.map { ("p-\($0.objectID)", planRepo.plannedMoment(of: $0) ?? .distantPast, .plan($0)) }
        ForEach(entries.sorted { $0.at < $1.at }, id: \.key) { row in
            switch row.entry {
            case .moment(let moment):
                if selecting {
                    Button {
                        if selected.contains(moment.objectID) { selected.remove(moment.objectID) }
                        else { selected.insert(moment.objectID) }
                    } label: {
                        HStack(spacing: 10) {
                            SelectionCircle(isOn: selected.contains(moment.objectID))
                            momentCard(moment, repo: repo)
                        }
                    }
                    .buttonStyle(DSPressEffect())
                } else {
                    SwipeDeleteRow(id: moment.objectID, openID: $openSwipeID) {
                        pendingDeleteMoment = moment
                    } content: {
                        NavigationLink {
                            MomentDetailView(moment: moment)
                        } label: {
                            momentCard(moment, repo: repo)
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .plan(let item):
                // 管理模式下计划卡照常渲染但不出选择圈、不可选(spec §三:批量删只针对记忆)
                planRow(item, state: meeting.statusRaw == MeetingStatus.finished.rawValue ? .missed : .todo)
            }
        }
        if let closed = day.closedAt {
            let sealCard = DarkCard {
                HStack {
                    Text("\(Fmt.hm.string(from: closed)) 封盘 · 晚安")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(moments.count) 条记忆")
                        .font(.system(size: 12)).foregroundStyle(DS.onDarkMuted)
                }
            }
            if selecting {
                sealCard
            } else {
                // 封盘卡左滑删这一天：仅空天可删（还有记忆先弹提示），序号自动前移
                SwipeDeleteRow(id: day.objectID, openID: $openSwipeID) {
                    if moments.isEmpty { pendingDeleteDay = day }
                    else { blockedDayCount = moments.count }
                } content: {
                    sealCard
                }
            }
        } else if meeting.statusRaw == MeetingStatus.ongoing.rawValue {
            Button("封盘") { showSeal = true }
                .buttonStyle(BluePillButtonStyle(fullWidth: true))
        }
    }

    /// 反馈⑧:计划卡一行——管理模式下不包选择圈(照常渲染,不可选);
    /// 非管理模式左滑删除,点卡片按三态分流(todo=编辑成回忆/missed=带坐标弹小地图/prepared=纯记录不可点)。
    @ViewBuilder
    private func planRow(_ item: CDPlanItem, state: PlanCardState) -> some View {
        let card = PlanTodoCard(item: item, state: state) {
            convert(item)
        }
        if selecting {
            card
        } else {
            SwipeDeleteRow(id: item.objectID, openID: $openSwipeID) {
                pendingDeletePlan = item
            } content: {
                card
                    .onTapGesture {
                        switch state {
                        case .todo: editingPlan = item          // 点卡 = 预填记忆表单(转化编辑路径)
                        case .missed:
                            if let place = item.place, place.latitude != 0 || place.longitude != 0 {
                                miniMapPlace = place             // 灰卡带坐标 → 临时小地图
                            }
                        case .prepared: break                    // 纯记录,不可点
                        }
                    }
            }
        }
    }

    /// 秒转化(点圆圈):无弹窗,待办卡原位过渡成记忆卡;转化前取消本机提醒
    private func convert(_ item: CDPlanItem) {
        if let id = item.id { ReminderScheduler.cancelPlans([id]) }
        withAnimation(.snappy) {
            _ = try? PlanItemRepository(context: context).convertToMoment(item)
        }
        SealReminder.refresh(context: context)
    }

    private func momentCard(_ moment: CDMoment, repo: MomentRepository) -> some View {
        let couples = CoupleRepository(context: context)
        let couple = try? couples.fetchCouple()
        let me = couple.flatMap { couples.currentPartner(of: $0) }
        let other = couple.flatMap { couples.otherPartner(of: $0) }
        let myEval = me.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let otherEval = other.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let partnerName = other?.name ?? "TA"
        let thumb = repo.photosSorted(moment).first?.thumbnailData

        return VStack(alignment: .leading, spacing: 6) {
            if let thumb, let ui = UIImage(data: thumb) {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                    // scaledToFill 的不可见溢出会替下方卡片抢走上方卡片的点击（clipShape 不裁命中区）；
                    // 装饰图彻底退出命中测试，点击全部交给卡片矩形
                    .allowsHitTesting(false)
            }
            HStack {
                Text(moment.title ?? "").font(.system(size: 17, weight: .semibold)).foregroundStyle(DS.ink)
                Text("\((MomentType(rawValue: moment.typeRaw) ?? .other).title) · \(moment.happenedAt.map { Fmt.hm.string(from: $0) } ?? "")")
                    .dsFootnote()
                Spacer()
                if let emoji = myEval?.moodEmoji { Text(emoji) }
            }
            VStack(alignment: .leading, spacing: 2) {
                if let myEval {
                    HStack(spacing: 4) {
                        Text("你").dsFootnote()
                        StarsView(stars: Int(myEval.stars))
                        if let comment = myEval.comment, !comment.isEmpty {
                            Text("“\(comment)”").font(.system(size: 12)).foregroundStyle(DS.ink).lineLimit(2)
                        }
                    }
                }
                if let otherEval {
                    HStack(spacing: 4) {
                        Text(partnerName).dsFootnote()
                        StarsView(stars: Int(otherEval.stars))
                        if let comment = otherEval.comment, !comment.isEmpty {
                            Text("“\(comment)”").font(.system(size: 12)).foregroundStyle(DS.ink).lineLimit(2)
                        }
                    }
                } else {
                    Text("\(partnerName) · 还没写").dsFootnote()
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.darkCard).stroke(DS.hairline, lineWidth: 1))
        // 命中区限定在卡片矩形内：scaledToFill 照片的不可见溢出不再劫持相邻卡片的点击
        .contentShape(Rectangle())
    }
}
