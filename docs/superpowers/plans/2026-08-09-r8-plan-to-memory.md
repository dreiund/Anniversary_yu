# 反馈⑧优化实现计划:计划 → 回忆 转化流水线

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 见面开始后行前计划整体并入时间线(已备划线卡/散插待办卡/结束后灰卡),划掉或编辑保存即转化成完整回忆并删除计划项。

**Architecture:** 转化收口在 `PlanItemRepository.convertToMoment`(创建 CDMoment 后删 CDPlanItem,源头消失天然防重,零 schema 变更);时间线渲染层把 moments 与 planItems 按合成时刻混排;MomentFormView 新增 `.fromPlan` 模式承载「点卡编辑成回忆」。

**Tech Stack:** SwiftUI + Core Data(NSPersistentCloudKitContainer),XcodeGen,XCTest/XCUITest。

**规范文件:** `docs/superpowers/specs/2026-08-09-r8-plan-to-memory-design.md`(§一~§七是本计划的需求原文)

## Global Constraints

- 最低系统 iOS 17.0(她机 17.3.1);禁用 iOS 18+ API
- 全部 UI 文案中文;复用既有 DS 组件(GroupedSection/SwipeDeleteRow/SelectableChip/BluePillButtonStyle 等)
- 新增 .swift 文件后必须跑 `./scripts/gen.sh`(XcodeGen)再构建
- 门禁:`./scripts/build.sh` 打印 ✅构建通过;`./scripts/test.sh` 打印 ✅测试通过(SourceKit 诊断是索引噪音,以脚本输出为准)
- **零 CloudKit schema 变更**:不新增实体/字段/关系(转化=删源防重是有意为之)
- 每个 commit 消息结尾带两行 trailer:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01UkuNQ16cmqL68DJxJSjefA`
- UI 测试模拟器 destination:`platform=iOS Simulator,name=iPhone 17 Pro`,derivedDataPath `.build`

---

### Task 1: 转化核心 —— MomentType 映射 + convertToMoment + plannedMoment

**Files:**
- Modify: `Domain/DomainEnums.swift`(文件尾追加 extension)
- Modify: `Persistence/PlanItemRepository.swift`(追加两个方法)
- Test: `Tests/PlanConversionTests.swift`(新建)

**Interfaces:**
- Consumes: `MomentRepository.create(in:type:title:body:happenedAt:photoDatas:myEvaluation:authorID:place:sealNewPastDayAt:)`(已存在);`PlaceResolver.resolve(_:context:couple:)`;`CoupleRepository.fetchCouple()/currentPartnerID(of:)`
- Produces: `PlanItemRepository.convertToMoment(_ item: CDPlanItem, now: Date = Date()) throws -> CDMoment?`;`PlanItemRepository.plannedMoment(of: CDPlanItem, calendar: Calendar = .current) -> Date?`;`MomentType.init(placeCategory: PlaceCategory)`——Task 4/5 直接调用这些签名

- [ ] **Step 1: DomainEnums.swift 尾部追加类型映射**

```swift
extension MomentType {
    /// 反馈⑧:计划转回忆时按地点类目推记忆类型
    init(placeCategory: PlaceCategory) {
        switch placeCategory {
        case .food, .cafe: self = .restaurant
        case .scenery: self = .sight
        case .shopping, .show: self = .activity
        case .stay: self = .stay
        case .other: self = .other
        }
    }
}
```

- [ ] **Step 2: PlanItemRepository.swift 追加合成时刻与转化方法**(放在 `stats(for:)` 之后、结构体收尾 `}` 之前)

```swift
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

    /// 反馈⑧:待办转化成回忆——创建 CDMoment 后删除计划项(源头消失,一条计划只生成一条回忆)。
    /// 时刻在未来或缺失时钳到 now(避免 dayForRecord 为未来日期造出「未来已封盘天」)。
    /// 只做数据:调用方负责在调用前用 item.id 取消本机提醒(ReminderScheduler.cancelPlans)。
    @discardableResult
    func convertToMoment(_ item: CDPlanItem, now: Date = Date()) throws -> CDMoment? {
        guard let meeting = item.meeting else { return nil }
        let couples = CoupleRepository(context: context)
        let couple = try? couples.fetchCouple()
        let authorID = couple.flatMap { couples.currentPartnerID(of: $0) }
        var place = item.place
        if place == nil, let text = item.placeText,
           !text.trimmingCharacters(in: .whitespaces).isEmpty, let couple {
            // 手输文字地点与记忆同管线归并(无坐标地点,档案页会提示补选点)
            place = PlaceResolver.resolve(
                PickedPlace(name: text.trimmingCharacters(in: .whitespaces),
                            latitude: 0, longitude: 0, categoryRaw: 0, existingPlaceID: nil),
                context: context, couple: couple)
        }
        let happenedAt = min(plannedMoment(of: item) ?? now, now)
        let category = place.flatMap { PlaceCategory(rawValue: $0.categoryRaw) } ?? .other
        let moment = try MomentRepository(context: context).create(
            in: meeting, type: MomentType(placeCategory: category),
            title: item.title ?? "", body: item.note, happenedAt: happenedAt,
            photoDatas: [], myEvaluation: nil, authorID: authorID, place: place)
        context.delete(item)
        try context.save()
        return moment
    }
```

- [ ] **Step 3: 写单元测试** `Tests/PlanConversionTests.swift`。参考 `Tests/` 里既有测试的内存容器搭法(如 `PlanItemRepositoryTests.swift` 的 setUp——用同一个 in-memory `PersistenceController`/测试容器工具;先读一个现有测试文件照抄基建)。测试用例:

```swift
// 1. testConvertMapsFields:建 couple+ongoing meeting(先 start 出开放天),add 计划项
//    (day=今天, time=今天 10:00, title "吃蟹家大院", note "人多要排队", place=某 CDPlace(categoryRaw=food)),
//    convertToMoment(now=今天 14:00)。断言:返回 moment.title=="吃蟹家大院"、body=="人多要排队"、
//    happenedAt==今天 10:00(过去时刻用计划时刻)、typeRaw==MomentType.restaurant.rawValue、
//    place===原 place;planItems 里该项已不存在(count 归零)。
// 2. testConvertClampsFutureToNow:计划时刻=明天 18:00,convertToMoment(now=今天 12:00)。
//    断言 happenedAt==今天 12:00。
// 3. testConvertMemoWithoutDate:day=nil time=nil,断言 happenedAt==now、typeRaw==other。
// 4. testConvertResolvesPlaceText:place=nil、placeText="老巷面馆",断言 moment.place != nil
//    且 name=="老巷面馆"(PlaceResolver 归并管线)。
// 5. testPlannedMomentComposition:day=8/12(任意时分), time=另一天的 18:30 →
//    plannedMoment 是 8/12 18:30;time=nil → 8/12 00:00;day=nil → nil。
```

- [ ] **Step 4: 跑门禁**:`./scripts/gen.sh && ./scripts/build.sh && ./scripts/test.sh`,三个 ✅
- [ ] **Step 5: Commit**:`反馈⑧T1:计划转回忆核心——convertToMoment(删源防重/未来钳当下/placeText 归并)+类目映射`

---

### Task 2: 计划表单时刻化(1A)

**Files:**
- Modify: `Features/Plan/PlanItemFormSheet.swift`

**Interfaces:**
- Consumes: 既有 `PlanItemRepository.add/update`(签名不变,继续写 day+time 两字段)
- Produces: 表单行为——「指定日期」开启后单行「时刻」;保存时 day 与 time 都写同一时刻值

- [ ] **Step 1: 状态改造**。删 `@State private var hasTime = false` 与 `@State private var time = Date()`;把 `day` 语义升级为完整时刻(命名保留 `day` 以减小 diff 也可,但要求把变量改名为 `moment` 提高可读性:`@State private var hasDay = false`、`@State private var moment = Date()`)。

- [ ] **Step 2: 表单块替换**(原 34-46 行的两层 Toggle):

```swift
                        Toggle("指定日期", isOn: $hasDay.animation())
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        if hasDay {
                            DatePicker("时刻", selection: $moment)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                        }
```

- [ ] **Step 3: loadIfEditing 兼容旧数据**(原 147-148 行):

```swift
        if let d = item.day {
            hasDay = true
            if let t = item.time {
                // 旧数据 day 与 time 分存:合成完整时刻
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: d)
                let hm = Calendar.current.dateComponents([.hour, .minute], from: t)
                comps.hour = hm.hour
                comps.minute = hm.minute
                moment = Calendar.current.date(from: comps) ?? d
            } else {
                // 旧「全天」条目:编辑时预填当日 09:00(spec §一)
                moment = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
            }
        }
```

- [ ] **Step 4: save() 改写值**(原 159-160 行):`let dayValue = hasDay ? moment : nil`、`let timeValue = hasDay ? moment : nil`(同一时刻写两字段,排序规则兼容旧数据不变)。`defaultRemindDate()` 里的 `of: day` 改 `of: moment`。

- [ ] **Step 5: 门禁** `./scripts/build.sh && ./scripts/test.sh`(既有 plannedFor 排序单元测试必须依旧全绿——它们直接构造 repo 数据,不经表单,预期不受影响)
- [ ] **Step 6: Commit**:`反馈⑧T2:计划表单时刻化——指定日期后单行「时刻」,存库 day/time 同值,旧全天编辑预填 9:00`

---

### Task 3: 见面详情三态 chips + 结束时取消未完成计划提醒

**Files:**
- Modify: `Features/Meetings/MeetingDetailView.swift`

**Interfaces:**
- Consumes: `MeetingStatus`、`ReminderScheduler.cancelPlans(_ ids: [UUID])`(已存在)
- Produces: 「计划」chip 仅 planned 状态显示;结束见面动作取消未完成计划项的提醒

- [ ] **Step 1: chips 条件渲染**(原 22-26 行):

```swift
                HStack(spacing: 4) {
                    SelectableChip(title: "时间线", isSelected: segment == 0) { segment = 0 }
                    SelectableChip(title: "路线图", isSelected: segment == 1) { segment = 1 }
                    // 反馈⑧:见面开始后行前计划整体并入时间线,「计划」入口只在计划中状态存在
                    if meeting.statusRaw == MeetingStatus.planned.rawValue {
                        SelectableChip(title: "计划", isSelected: segment == 2) { segment = 2 }
                    }
                }
```

- [ ] **Step 2: segment 保护**。`.onChange(of: segment)` 旁追加:

```swift
        .onChange(of: meeting.statusRaw) { _, newValue in
            if segment == 2, newValue != MeetingStatus.planned.rawValue { segment = 0 }
        }
```

并在 body 的 `else` 分支(原 38-40 行)加兜底:`PlanView` 只在 planned 时可达,非 planned 直接展示时间线:

```swift
            } else if meeting.statusRaw == MeetingStatus.planned.rawValue {
                PlanView(meeting: meeting)
            } else {
                ScrollView {
                    TimelineListView(meeting: meeting, selecting: selecting, selected: $selected)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.bottom, DS.Spacing.md)
                }
            }
```

- [ ] **Step 3: 结束见面取消未完成计划提醒**(原 92-100 行 alert 的结束按钮):

```swift
            Button("结束见面", role: .destructive) {
                // 反馈⑧:见面结束,没做成的计划变灰卡,它们的提醒闹钟一并取消
                let pendingIDs = ((meeting.planItems as? Set<CDPlanItem>) ?? [])
                    .filter { !$0.isDone }
                    .compactMap(\.id)
                ReminderScheduler.cancelPlans(pendingIDs)
                try? MeetingRepository(context: context).end(meeting, at: Date())
                SealReminder.refresh(context: context)
            }
```

- [ ] **Step 4: 门禁** `./scripts/build.sh && ./scripts/test.sh`
- [ ] **Step 5: Commit**:`反馈⑧T3:「计划」chip 仅计划中显示(开始后并入时间线),结束见面取消未完成计划提醒`

---

### Task 4: MomentFormView 新增 .fromPlan 模式(点卡编辑成回忆)

**Files:**
- Modify: `Features/Moments/MomentFormView.swift`

**Interfaces:**
- Consumes: `PlanItemRepository.plannedMoment(of:)`(T1);`ReminderScheduler.cancelPlans`;既有 create 流程(staleDay/backfillSeal 补录询问照常工作)
- Produces: `MomentFormMode.fromPlan(CDPlanItem)`——Task 5 的时间线点卡入口用 `MomentFormView(mode: .fromPlan(item))`

- [ ] **Step 1: enum 加 case**:

```swift
enum MomentFormMode {
    case create(CDMeeting)
    case edit(CDMoment)
    case fromPlan(CDPlanItem)   // 反馈⑧:待办卡点开编辑,保存=创建回忆+删计划(转化)
}
```

- [ ] **Step 2: 预填**。`loadIfEditing()` 开头追加(guard 之前):

```swift
        if case let .fromPlan(item) = mode {
            let repo = PlanItemRepository(context: context)
            title = item.title ?? ""
            bodyText = item.note ?? ""
            happenedAt = min(repo.plannedMoment(of: item) ?? Date(), Date())
            if let place = item.place {
                locationName = place.name ?? ""
                if place.latitude != 0 || place.longitude != 0 {
                    coords = (place.latitude, place.longitude)
                }
                locationCategoryRaw = place.categoryRaw
                linkedPlaceID = place.id
                type = MomentType(placeCategory: PlaceCategory(rawValue: place.categoryRaw) ?? .other)
            } else {
                locationName = item.placeText ?? ""
                type = .other
            }
            return
        }
```

- [ ] **Step 3: save()/doCreate 接线**。`save()` 的 switch 加分支(逻辑与 `.create` 相同,meeting 从 item 取):

```swift
        case let .fromPlan(item):
            guard let meeting = item.meeting else { dismiss(); return }
            let meetingRepo = MeetingRepository(context: context)
            let stale = (try? meetingRepo.staleOpenDay(in: meeting, now: Date(), recordAt: happenedAt)) ?? nil
            if let stale { staleDay = stale; return }
            if meetingRepo.wouldOpenNewPastDay(in: meeting, at: happenedAt) {
                backfillSeal = BackfillSealTarget(id: happenedAt)
                return
            }
            doCreate(in: meeting)
```

`staleDay`/`backfillSeal` 两个 sheet 回调里 `if case let .create(meeting) = mode` 的判断改为同时接受 fromPlan(提取 helper):

```swift
    private var createTargetMeeting: CDMeeting? {
        switch mode {
        case let .create(meeting): meeting
        case let .fromPlan(item): item.meeting
        case .edit: nil
        }
    }
```

两处 sheet 回调改为 `if let meeting = createTargetMeeting { ... }`。

`doCreate(in:sealNewPastDayAt:)` 尾部(`SealReminder.refresh` 之前)追加:

```swift
        if case let .fromPlan(item) = mode {
            // 转化收尾:计划项退场(取消提醒后删除)——与秒转化同语义
            if let id = item.id { ReminderScheduler.cancelPlans([id]) }
            try? PlanItemRepository(context: context).delete(item)
        }
```

- [ ] **Step 4: 标题与评价栏**。`navigationTitle` 三态:`.edit` → 编辑记忆;`.fromPlan` → 补全这段回忆;`.create` → 新的记忆(用 switch 替换现有三元)。`isEdit` 保持只对 `.edit` 为 true(fromPlan 自动获得评价栏与「选择照片」——正是 spec「评价照片栏目在从日程变到回忆后加入」)。

- [ ] **Step 5: 门禁** `./scripts/build.sh && ./scripts/test.sh`
- [ ] **Step 6: Commit**:`反馈⑧T4:MomentFormView .fromPlan 模式——预填计划字段,保存即转化(创建回忆+删计划+取消提醒)`

---

### Task 5: 时间线融合渲染(已备/散插待办/接下来/灰卡)+ 全部交互

**Files:**
- Create: `Features/Meetings/PlanCardViews.swift`
- Modify: `Features/Meetings/TimelineListView.swift`

**Interfaces:**
- Consumes: T1 `convertToMoment`/`plannedMoment`;T4 `.fromPlan`;`PlanItemFormSheet(meeting:item:)`;`PlaceMiniMapSheet(place:)`;`SwipeDeleteRow(id:openID:onDelete:content:)`;`ReminderScheduler.cancelPlans`
- Produces: 完整时间线行为(spec §三);`PlanTodoCard(item:state:)` 视图

- [ ] **Step 1: 新建 `Features/Meetings/PlanCardViews.swift`**:

```swift
import SwiftUI
import CoreData

/// 反馈⑧:时间线里的计划卡三态
enum PlanCardState {
    case todo       // 进行中待办:虚线框+空圈,点圈转化
    case prepared   // 行前已备:划线+实勾,纯记录
    case missed     // 结束后没做成:灰卡
}

struct PlanTodoCard: View {
    @Environment(\.managedObjectContext) private var context
    let item: CDPlanItem
    let state: PlanCardState
    var onToggle: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            switch state {
            case .todo:
                Button { onToggle?() } label: {
                    Circle().strokeBorder(DS.inkMuted, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("划掉 \(item.title ?? "")")
            case .prepared:
                ZStack {
                    Circle().fill(DS.chipBorder).frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
            case .missed:
                EmptyView()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(state == .todo ? DS.ink : DS.inkMuted)
                    .strikethrough(state == .prepared)
                if let sub = subtitle {
                    Text(sub).dsFootnote()
                }
            }
            Spacer(minLength: 0)
            if state == .missed {
                Text("没做成 · 下次再来")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.inkMuted)
                    .padding(.vertical, 2).padding(.horizontal, 7)
                    .overlay(Capsule().stroke(DS.chipBorder, lineWidth: 1))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .contentShape(Rectangle())
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let moment = PlanItemRepository(context: context).plannedMoment(of: item) {
            let prefix = state == .missed ? "原定 " : ""
            let text = item.time == nil ? Fmt.monthDayWeek.string(from: moment)
                : "\(Fmt.monthDayWeek.string(from: moment)) \(Fmt.hm.string(from: moment))"
            parts.append(prefix + text)
        }
        if let placeName = item.place?.name ?? item.placeText, !placeName.isEmpty {
            parts.append(placeName)
        }
        if state != .prepared, let note = item.note, !note.isEmpty {
            parts.append("备注:\(note)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var background: some View {
        switch state {
        case .todo:
            RoundedRectangle(cornerRadius: DS.Radius.darkCard)
                .fill(DS.canvas.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.darkCard)
                    .strokeBorder(DS.chipBorder, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        case .prepared:
            RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.parchment.opacity(0.9))
        case .missed:
            RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.chipBorder.opacity(0.35))
        }
    }
}
```

(若 `DS.chipBorder`/`DS.inkMuted`/`DS.canvas`/`Fmt.monthDayWeek` 等名字与实际不符,以 `Support/DesignSystem.swift`、`Support/Formatters.swift` 里的真实名字为准就近替换——实现前先打开这两个文件核对。)

- [ ] **Step 2: TimelineListView 数据层**。新增 fetch/状态(init 里同步加):

```swift
    @FetchRequest private var plansFetch: FetchedResults<CDPlanItem>
    @State private var showAddPlan = false
    @State private var editingPlan: CDPlanItem?
    @State private var pendingDeletePlan: CDPlanItem?
    @State private var miniMapPlace: CDPlace?
// init 内:
        _plansFetch = FetchRequest(sortDescriptors: [],
                                   predicate: NSPredicate(format: "meeting == %@", meeting))
```

body 顶部注册行改为 `let _ = (momentsFetch.count, daysFetch.count, evalsFetch.count, plansFetch.count)`,并准备派生数据:

```swift
        let planRepo = PlanItemRepository(context: context)
        let isOngoing = meeting.statusRaw == MeetingStatus.ongoing.rawValue
        let isFinished = meeting.statusRaw == MeetingStatus.finished.rawValue
        let showPlans = isOngoing || isFinished
        let allPlans = showPlans ? Array(plansFetch) : []
        let prepared = allPlans.filter(\.isDone).sorted { $0.sortIndex < $1.sortIndex }
        let pendingPlans = allPlans.filter { !$0.isDone }
        // 散插:时刻落在某个已有天的自然日内 → 进那天;其余(未来/备忘)→ 尾组
        let calendar = Calendar.current
        let dayDates = grouped.compactMap { $0.day.openedAt }
        func belongsToExistingDay(_ item: CDPlanItem) -> Bool {
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
```

- [ ] **Step 3: 渲染结构**。LazyVStack 内容改为:

```swift
            if grouped.isEmpty && prepared.isEmpty && pendingPlans.isEmpty {
                Text("还没有记录 · 点底栏 ⊕ 记下第一条")…(原样)
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
```

- [ ] **Step 4: daySection 混排**。签名加 `plans: [CDPlanItem]` 与 `planRepo: PlanItemRepository`;moments 的 ForEach 改成合成列表:

```swift
        // 混排:回忆按 happenedAt、计划按合成时刻(全天=00:00 排组首)
        enum Entry { case moment(CDMoment); case plan(CDPlanItem) }
        let entries: [(key: String, at: Date, entry: Entry)] =
            moments.map { ("m-\($0.objectID)", $0.happenedAt ?? .distantPast, .moment($0)) }
            + plans.map { ("p-\($0.objectID)", planRepo.plannedMoment(of: $0) ?? .distantPast, .plan($0)) }
        ForEach(entries.sorted { $0.at < $1.at }, id: \.key) { row in
            switch row.entry {
            case .moment(let moment): (原有 selecting/SwipeDeleteRow 两分支渲染,原样搬入)
            case .plan(let item):
                planRow(item, state: meeting.statusRaw == MeetingStatus.finished.rawValue ? .missed : .todo)
            }
        }
```

(管理模式 `selecting` 下 `.plan` 行照常渲染 `planRow`,不包选择按钮——spec §三:批量删只针对记忆。)

- [ ] **Step 5: planRow 与交互**。TimelineListView 内追加:

```swift
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

    private func convert(_ item: CDPlanItem) {
        if let id = item.id { ReminderScheduler.cancelPlans([id]) }
        withAnimation(.snappy) {
            _ = try? PlanItemRepository(context: context).convertToMoment(item)
        }
        SealReminder.refresh(context: context)
    }
```

- [ ] **Step 6: sheets 与删除确认**。body 修饰符区追加:

```swift
        .sheet(isPresented: $showAddPlan) { PlanItemFormSheet(meeting: meeting, item: nil) }
        .sheet(item: $editingPlan) { MomentFormView(mode: .fromPlan($0)) }
        .sheet(item: $miniMapPlace) { PlaceMiniMapSheet(place: $0) }
        .alert("删除这条计划?", isPresented: Binding(get: { pendingDeletePlan != nil },
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
            Text("只删这条计划,不影响任何记忆。")
        }
```

`CDPlanItem`/`CDPlace` 若还没 `Identifiable` 扩展(sheet(item:) 需要),文件尾部按需补 `extension CDPlanItem: Identifiable {}`(`CDPlace` 在 R7 已有,先搜索确认避免重复声明)。

- [ ] **Step 7: gen+门禁**:`./scripts/gen.sh && ./scripts/build.sh && ./scripts/test.sh`
- [ ] **Step 8: Commit**:`反馈⑧T5:时间线融合——行前已备/散插待办/接下来/灰卡三态卡与全部交互(转化/编辑/删/加待办/小地图)`

---

### Task 6: 种子 + UI 回归 + 全量验证

**Files:**
- Modify: `Support/DebugSeeder.swift`
- Modify: `UITests/MapFilterReproTests.swift`

**Interfaces:**
- Consumes: 前五个任务的全部行为
- Produces: `testRound8PlanFlow` 走通「已备卡→待办卡→点圈转化→结束见面→灰卡」

- [ ] **Step 1: 种子扩充**。`--seed-map-demo` 主种子(现有 `去码头拍日落` 计划保持)追加,紧跟其后:

```swift
        // 反馈⑧:行前已备划线卡 + 备忘待办(接下来组)
        let ticket = try? PlanItemRepository(context: context).add(
            to: meeting, day: nil, time: nil, title: "买火车票", note: nil,
            placeText: nil, authorID: mePartner.id)
        ticket?.isDone = true
        _ = try? PlanItemRepository(context: context).add(
            to: meeting, day: nil, time: nil, title: "给她妈带特产", note: nil,
            placeText: nil, authorID: mePartner.id)
        try? context.save()
```

(`mePartner` 用该函数里已有的当前伴侣变量名;没有就照现有 `去码头拍日落` 的 authorID 写法。)

- [ ] **Step 2: 写 `testRound8PlanFlow`**(加在 `testSinglePinRenders` 之后):

```swift
    /// 反馈⑧:计划→回忆转化流水线(已备卡/待办卡/点圈转化/结束后灰卡)
    @MainActor
    func testRound8PlanFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()
        app.buttons["足迹"].tap()
        let card = app.staticTexts["上海"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), "进行中卡未出现")
        card.tap()
        // 进行中:行前已备 + 待办卡 + 接下来组
        XCTAssertTrue(app.staticTexts["行前已备 · 1"].waitForExistence(timeout: 5), "已备组未出现")
        XCTAssertTrue(app.staticTexts["买火车票"].exists, "已备划线卡未出现")
        XCTAssertTrue(app.staticTexts["接下来 · 还没做"].exists, "接下来组未出现")
        XCTAssertTrue(app.staticTexts["给她妈带特产"].exists, "备忘待办未出现")
        // 「计划」chip 应已消失(进行中)
        XCTAssertFalse(app.buttons["计划"].exists, "进行中不应再有计划 chip")
        attach(app, name: "R8-1-进行中时间线")
        // 点圈秒转化「去码头拍日落」(今天全天待办,散插在今天组)
        let toggle = app.buttons["划掉 去码头拍日落"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "待办圈未出现")
        toggle.tap()
        sleep(1)
        XCTAssertFalse(app.buttons["划掉 去码头拍日落"].exists, "转化后圈应消失")
        XCTAssertTrue(app.staticTexts["去码头拍日落"].exists, "转化后的记忆卡不见了")
        attach(app, name: "R8-2-转化后")
        // 结束见面 → 灰卡
        app.buttons["结束见面"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        app.alerts.firstMatch.buttons["结束见面"].tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["没做成的计划"].waitForExistence(timeout: 5), "灰卡组未出现")
        XCTAssertTrue(app.staticTexts["给她妈带特产"].exists, "灰卡未出现")
        attach(app, name: "R8-3-结束后灰卡")
    }
```

- [ ] **Step 3: 先单跑本用例**:`xcodebuild test … -only-testing:AnniversaryUITests/MapFilterReproTests/testRound8PlanFlow -resultBundlePath <scratch>/r8flow.xcresult -quiet`,失败则导出截图诊断(断言文案与实际 UI 对齐,必要时微调断言而非产品代码——产品行为以 spec 为准)。**注意**:种子变更可能影响既有用例(足迹列表/testRound7MapLook 截图内容变化是预期,断言失败才需要处理)。
- [ ] **Step 4: 全量**:`./scripts/test.sh` + 全 UI 套件 `-only-testing:AnniversaryUITests`,全绿。
- [ ] **Step 5: Commit**:`反馈⑧T6:种子扩已备/备忘计划项 + testRound8PlanFlow 全流程回归`

---

## Self-Review 记录

- spec §一~§七 均有对应任务(§一→T2;§二→T3+T6 断言;§三→T5;§四→T1+T4+T5;§五表格→T3/T5 组合;§六→T1 注释+T3/T5 调用方取消;§七→T1 单测+T6 UI)
- 类型/签名一致性:`convertToMoment`/`plannedMoment`(T1 定义,T4/T5 消费);`.fromPlan`(T4 定义,T5 消费);`PlanTodoCard(item:state:onToggle:)`(T5 内自洽)
- 已知风险提示给实现者:DS 色/字体名与 Fmt 格式器名以 `Support/DesignSystem.swift`、`Support/Formatters.swift` 实际为准;`CDPlanItem: Identifiable` 可能已在别处声明,先搜再加;daySection 内新 enum 需放函数外(嵌套在 ViewBuilder 里不合法)——放文件私有作用域
