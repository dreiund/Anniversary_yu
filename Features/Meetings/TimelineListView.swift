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
        // 反馈⑨T4:备忘(day == nil)从主时间线剥离——已备组/散插/tail/灰卡从此只含日程；
        // 备忘改在 MeetingDetailView 的左缘侧签弹窗里独立展示(纯划线,永不转化，见 MemoListSheet)
        let memos = allPlans.filter { $0.day == nil }
        let prepared = allPlans.filter { $0.day != nil }.filter(\.isDone).sorted { $0.sortIndex < $1.sortIndex }
        let pendingPlans = allPlans.filter { $0.day != nil }.filter { !$0.isDone }
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
            // 反馈⑨T4修(评审 Low):空态判断纳入 memos——只有备忘时,侧签已经露出「备忘 N」,
            // 主时间线不该再喊「还没有记录」制造矛盾
            if grouped.isEmpty && prepared.isEmpty && pendingPlans.isEmpty && memos.isEmpty {
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
        // 反馈⑨T4:备忘入口挪到侧签弹窗的「＋ 加备忘」里，这里保持日程直达
        .sheet(isPresented: $showAddPlan) { PlanItemFormSheet(meeting: meeting, item: nil, initialMode: .schedule) }
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
        // 反馈⑧修(评审 Important):管理模式下计划卡纯展示——onToggle 冻结为 nil 且整卡 disabled,
        // 待办圈不可误触(手滑点到圈不再静默创建回忆/删计划);非管理模式才接上真实回调。
        // 反馈⑨T4:onToggle 不再秒转化——点圈与点卡统一打开 .fromPlan 补全表单(与下方 onTapGesture
        // 的 .todo 分支同一目标),转化前先在表单里补全再由用户确认保存。
        let card = PlanTodoCard(item: item, state: state, onToggle: selecting ? nil : { editingPlan = item })
            .disabled(selecting)
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

/// 反馈⑨T4:备忘从时间线主流剥离后的独立弹窗——纯记录列表,勾选=划线(toggleDone)+勾掉取消提醒,永不转化成回忆；
/// 这正是与待办卡的本质区别:待办卡点圈/点卡都是"补全表单→转成记忆"，备忘卡打勾只是划掉。
/// 由 MeetingDetailView 持有 showMemos 状态并挂在 ScrollView 容器层展示(侧签始终可见不随时间线滚走)，
/// memos 由调用方算好传入，这里只管渲染与增删改。
/// 反馈⑨T4修(评审 Moderate):行样式与 PlanView.memoRow 对齐(标题 14pt/勾钮 DSPressEffect/备注单行)，
/// 并补上长按 contextMenu「编辑」——此前只能删除重建,改个错字都做不到。
struct MemoListSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let meeting: CDMeeting
    // 反馈⑩bug2:自持 FetchRequest——之前接收父层传入的数组快照,行内勾选写库后无任何观察者,
    // 界面不重画(重进才见划线)。FetchRequest 对属性变化(isDone)也响应,勾选即时上屏
    @FetchRequest private var memosFetch: FetchedResults<CDPlanItem>
    @State private var memoAddSheet = false
    @State private var editingItem: CDPlanItem?

    init(meeting: CDMeeting) {
        self.meeting = meeting
        _memosFetch = FetchRequest(sortDescriptors: [SortDescriptor(\.sortIndex)],
                                   predicate: NSPredicate(format: "meeting == %@ AND day == nil", meeting))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(memosFetch, id: \.objectID) { item in
                    MemoRow(item: item) { editingItem = item }
                }
            }
            .listStyle(.plain)
            .navigationTitle("备忘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("＋ 加备忘") { memoAddSheet = true }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $memoAddSheet) {
            PlanItemFormSheet(meeting: meeting, item: nil, initialMode: .memo)
        }
        // initialMode 留空:item.day == nil 已经让 PlanItemFormSheet 自动判成备忘模式(同 PlanView.editingItem 用法)
        .sheet(item: $editingItem) { PlanItemFormSheet(meeting: meeting, item: $0) }
    }

}

/// 反馈⑫:备忘行独立成 struct 并 @ObservedObject 订阅——List 对同 id 行有值缓存,
/// 只靠 FetchRequest 整体失效时第 2+n 次勾选不重绘(数据已变、界面不动);
/// NSManagedObject 自带 ObservableObject,行级订阅让每次 toggle 必驱动本行重绘
/// (同款方案:MomentDetailView 的 @ObservedObject,P1 反馈轮已验证)
private struct MemoRow: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var item: CDPlanItem
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                toggle()
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(item.isDone ? DS.actionBlue : DS.chipBorder)
            }
            .buttonStyle(DSPressEffect())
            // 动态无障碍标签:也让「第 n 次点按重绘」可被 UI 测试断言(反馈⑫回归锁)
            .accessibilityLabel(item.isDone ? "恢复 \(item.title ?? "")" : "划掉 \(item.title ?? "")")
            Text(item.title ?? "")
                .font(.system(size: 14))
                .strikethrough(item.isDone, color: DS.inkMuted)
                .foregroundStyle(item.isDone ? DS.inkMuted : DS.ink)
            if let note = item.note, !note.isEmpty { Text(note).dsFootnote().lineLimit(1) }
            Spacer()
        }
        .contentShape(Rectangle())
        // P6-T6:备忘正文点击=勾选——整行(不止圆圈)可 tap 触发 toggle,与 PlanView.memoRow 同构；
        // 圆圈自身是 Button 会吃掉点击，不会与本行 onTapGesture 重复触发；tap 与 swipeActions/
        // contextMenu(长按)手势互不冲突，无需额外处理
        .onTapGesture { toggle() }
        .swipeActions {
            Button("删除", role: .destructive) {
                let id = item.id
                try? PlanItemRepository(context: context).delete(item)
                if let id { ReminderScheduler.cancelPlans([id]) }
            }
        }
        .contextMenu {
            Button("编辑") { onEdit() }
            Button("删除", role: .destructive) {
                let id = item.id
                try? PlanItemRepository(context: context).delete(item)
                if let id { ReminderScheduler.cancelPlans([id]) }
            }
        }
    }

    /// 备忘勾选:划掉即取消提醒(取消勾选不恢复提醒，同 PlanView.memoRow 口径)
    private func toggle() {
        try? PlanItemRepository(context: context).toggleDone(item)
        if item.isDone, let id = item.id {
            ReminderScheduler.cancel(id: ReminderPlanner.planID(id))
        }
    }
}
