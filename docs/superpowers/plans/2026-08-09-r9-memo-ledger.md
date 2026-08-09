# 反馈⑨实现计划:备忘独立化 / 划掉即补全 / 日程查看+导航 / 小本本新壳

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 备忘从计划流水线独立(双模式表单+时间线左缘侧签弹窗)、待办划掉直接弹补全表单、行前日程只读查看页+地点导航、小本本列表按用户设计图换新壳(米色)。

**Architecture:** 备忘=day==nil 的 CDPlanItem(零迁移);时间线渲染层把备忘从卡流剥离进侧签 sheet;转化唯一入口收敛为 .fromPlan 表单(删 convertToMoment);小本本只换列表壳不动规则层。

**Tech Stack:** SwiftUI + Core Data,XcodeGen,XCTest/XCUITest。

**规范:** `docs/superpowers/specs/2026-08-09-r9-memo-ledger-design.md`(§一~§五)

## Global Constraints

- iOS 17.0 floor;全中文文案;复用 DS 组件;新 .swift 文件先 `./scripts/gen.sh`
- 门禁:`./scripts/build.sh` ✅构建通过;`./scripts/test.sh` ✅测试通过;UI destination `platform=iOS Simulator,name=iPhone 17 Pro`,derivedDataPath `.build`
- 零 CloudKit schema 变更
- 每个 commit 结尾两行 trailer:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01UkuNQ16cmqL68DJxJSjefA`

---

### Task 1: PlanItemFormSheet 双模式(日程|备忘)

**Files:** Modify: `Features/Plan/PlanItemFormSheet.swift`

**Interfaces:**
- Produces: `PlanItemFormSheet(meeting:item:initialMode:)`——新增 `initialMode: PlanFormMode? = nil`(nil=自动判);`enum PlanFormMode { case schedule, memo }`(文件内声明,Task 4 的「＋加备忘」用 `initialMode: .memo`)
- 保存契约:备忘模式 day/time/place/placeText/remindAt 全 nil 且取消原提醒;日程模式 day=time=时刻值(时刻必填,无开关)

- [ ] **Step 1: 状态与枚举**。文件顶部(struct 外)加 `enum PlanFormMode { case schedule, memo }`;struct 加 `let initialMode: PlanFormMode?`(init 默认 nil,置于 item 参数后)与 `@State private var formMode: PlanFormMode = .schedule`;删 `@State private var hasDay`(时刻必填,开关消失),`moment` 保留。
- [ ] **Step 2: 表单块重排**。第一个 GroupedSection 改为:

```swift
                    Picker("", selection: $formMode.animation()) {
                        Text("日程").tag(PlanFormMode.schedule)
                        Text("备忘").tag(PlanFormMode.memo)
                    }
                    .pickerStyle(.segmented)
                    GroupedSection {
                        HStack {
                            Text("事项").dsBody()
                            TextField(formMode == .memo ? "如 带伞" : "如 G102 高铁", text: $title)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        if formMode == .schedule {
                            DS.hairline.frame(height: 1).padding(.leading, 14)
                            DatePicker("时刻", selection: $moment)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                            DS.hairline.frame(height: 1).padding(.leading, 14)
                            Toggle("提醒我", isOn: /* 现有自定义 Binding 原样 */)
                            /* 提醒块原样保留在 schedule 分支内 */
                        }
                    }
```

第二个 GroupedSection(备注+地点):备注行永远显示;地点行包 `if formMode == .schedule`。navigationTitle 按模式:`item == nil ? (formMode == .memo ? "添加备忘" : "添加日程") : "编辑"`。
- [ ] **Step 3: loadIfEditing/初始模式**。`onAppear` 開頭:`formMode = initialMode ?? ((item?.day == nil && item != nil) ? .memo : .schedule)`;时刻合成逻辑保留(旧全天预填 09:00)。新建且 initialMode==nil 默认 .schedule。
- [ ] **Step 4: save() 按模式**:

```swift
        let isMemo = formMode == .memo
        let dayValue: Date? = isMemo ? nil : moment
        let timeValue: Date? = isMemo ? nil : moment
        let remindValue: Date? = (!isMemo && remindOn) ? remindDate : nil
        // 地点:备忘模式一律 nil(place/placeText 同);日程模式走现有 PlaceResolver 逻辑
```

备忘模式保存后无条件 `ReminderScheduler.cancel(id: ReminderPlanner.planID(id))`(原日程切备忘时清野提醒);日程模式提醒调度逻辑原样。
- [ ] **Step 5: 门禁**(build+test)→ **Step 6: Commit**:`反馈⑨T1:计划表单双模式——日程(时刻必填)|备忘(仅事项+备注),备忘保存清空日程字段并取消提醒`

---

### Task 2: PlanItemDetailSheet 查看页 + 小地图导航按钮

**Files:** Create: `Features/Plan/PlanItemDetailSheet.swift`;Modify: `Features/Places/PlaceMiniMapSheet.swift`

**Interfaces:**
- Consumes: `PlanItemRepository.plannedMoment(of:)`;`PlaceMiniMapSheet(place:)`;`PlanItemFormSheet`
- Produces: `PlanItemDetailSheet(item: CDPlanItem)`(Task 3 的 PlanView 日程行点击用);`openInMapsNavigation(place:)` 免费函数(两处共用)

- [ ] **Step 1: 新建 PlanItemDetailSheet.swift**:

```swift
import SwiftUI
import MapKit
import CoreData

/// 反馈⑨:行前日程只读查看页——点行先看,右上「编辑」才进表单;带坐标地点可直接导航
struct PlanItemDetailSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let item: CDPlanItem
    @State private var showEdit = false
    @State private var showMiniMap = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title ?? "").dsPageTitle()
                        if let moment = PlanItemRepository(context: context).plannedMoment(of: item) {
                            HStack(spacing: 4) {
                                Text(item.time == nil
                                     ? Fmt.monthDayWeek.string(from: moment)
                                     : "\(Fmt.monthDayWeek.string(from: moment)) \(Fmt.hm.string(from: moment))")
                                    .dsCaption()
                                if item.remindAt != nil { Text("⏰").font(.system(size: 11)) }
                            }
                        }
                    }
                    if let place = item.place ?? nil {
                        GroupedSection {
                            HStack {
                                Button {
                                    if place.latitude != 0 || place.longitude != 0 { showMiniMap = true }
                                } label: {
                                    Text("📍 \(place.name ?? "")").dsBody().foregroundStyle(DS.ink)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                if place.latitude != 0 || place.longitude != 0 {
                                    Button("导航") { openInMapsNavigation(place: place) }
                                        .buttonStyle(BluePillButtonStyle())
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                    } else if let text = item.placeText, !text.isEmpty {
                        GroupedSection {
                            Text("📍 \(text)").dsBody()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                    }
                    if let note = item.note, !note.isEmpty {
                        GroupedSection {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("备注").dsFootnote()
                                Text(note).dsBody()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle("日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("编辑") { showEdit = true } }
            }
            .sheet(isPresented: $showEdit, onDismiss: {
                // 表单里删除了此项 → 查看页失去对象,跟着退场
                if item.managedObjectContext == nil || item.isDeleted { dismiss() }
            }) {
                if let meeting = item.meeting { PlanItemFormSheet(meeting: meeting, item: item) }
            }
            .sheet(isPresented: $showMiniMap) {
                if let place = item.place { PlaceMiniMapSheet(place: place) }
            }
        }
    }
}

/// 反馈⑨:跳苹果地图对某地点开导航(小地图/日程查看页共用)
func openInMapsNavigation(place: CDPlace) {
    let coord = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coord))
    mapItem.name = place.name
    mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
}
```

- [ ] **Step 2: PlaceMiniMapSheet 加导航**。toolbar 加:

```swift
                ToolbarItem(placement: .confirmationAction) {
                    if place.latitude != 0 || place.longitude != 0 {
                        Button("导航") { openInMapsNavigation(place: place) }
                    }
                }
```

- [ ] **Step 3: gen+门禁** → **Step 4: Commit**:`反馈⑨T2:日程只读查看页(编辑入口分离)+ 小地图与查看页统一「导航」按钮`

---

### Task 3: PlanView 改造(备忘紧凑列表行 + 日程行点击=查看)

**Files:** Modify: `Features/Plan/PlanView.swift`

**Interfaces:**
- Consumes: T2 `PlanItemDetailSheet`;T1 表单(编辑入口不变)
- Produces: planned 态行为——日程行 tap→查看 sheet;备忘区 GroupedSection 行式

- [ ] **Step 1: 状态**。加 `@State private var viewingItem: CDPlanItem?`;sheet 区加 `.sheet(item: $viewingItem) { PlanItemDetailSheet(item: $0) }`。
- [ ] **Step 2: planRow 点击改**(原 232 行):`else { viewingItem = item }`(编辑入口移进查看页)。
- [ ] **Step 3: 备忘区重排**(原 76-83 行 LazyVGrid 整块替换):

```swift
                if !sections.undated.isEmpty {
                    Text("备忘").dsSectionTitle()
                    GroupedSection {
                        ForEach(Array(sections.undated.enumerated()), id: \.element.objectID) { i, item in
                            VStack(spacing: 0) {
                                if selecting {
                                    memoRow(item)
                                } else {
                                    SwipeDeleteRow(id: item.objectID, openID: $openSwipeID,
                                                   buttonWidth: 56, cornerRadius: 10,
                                                   buttonInset: 4, showsLabel: false) {
                                        let id = item.id
                                        try? PlanItemRepository(context: context).delete(item)
                                        if let id { ReminderScheduler.cancelPlans([id]) }
                                    } content: {
                                        memoRow(item)
                                    }
                                }
                                if i < sections.undated.count - 1 {
                                    DS.hairline.frame(height: 1).padding(.leading, 14)
                                }
                            }
                        }
                    }
                }
```

memoChip 函数替换为 memoRow(紧凑行,保留 contextMenu):

```swift
    private func memoRow(_ item: CDPlanItem) -> some View {
        HStack(spacing: 10) {
            if selecting {
                SelectionCircle(isOn: selected.contains(item.objectID), size: 20)
            } else {
                Button {
                    try? PlanItemRepository(context: context).toggleDone(item)
                    if item.isDone, let id = item.id {
                        ReminderScheduler.cancel(id: ReminderPlanner.planID(id))
                    }
                } label: {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(item.isDone ? DS.actionBlue : DS.chipBorder)
                }
                .buttonStyle(DSPressEffect())
            }
            Text(item.title ?? "")
                .font(.system(size: 14))
                .strikethrough(item.isDone, color: DS.inkMuted)
                .foregroundStyle(item.isDone ? DS.inkMuted : DS.ink)
            if let note = item.note, !note.isEmpty {
                Text(note).dsFootnote().lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { if selecting { toggleSelection(item.objectID) } }
        .contextMenu {
            Button("编辑") { editingItem = item }
            Button("删除", role: .destructive) {
                let id = item.id
                try? PlanItemRepository(context: context).delete(item)
                if let id { ReminderScheduler.cancelPlans([id]) }
            }
        }
    }
```

- [ ] **Step 4: 底部按钮**。「添加日程」改成两个:`Button("添加备忘") { addMode = .memo; showAdd = true }`(灰样式 `.font(.system(size: 14)).foregroundStyle(DS.inkMuted)`)+ 既有蓝丸「添加日程」(`addMode = .schedule`);加 `@State private var addMode: PlanFormMode = .schedule`,showAdd sheet 改 `PlanItemFormSheet(meeting: meeting, item: nil, initialMode: addMode)`。
- [ ] **Step 5: 门禁** → **Step 6: Commit**:`反馈⑨T3:行前页——日程行点击改查看页,备忘区改紧凑列表行,底栏添加日程|备忘分立`

---

### Task 4: TimelineListView(侧签弹窗 + 划掉即弹表单)

**Files:** Modify: `Features/Meetings/TimelineListView.swift`

**Interfaces:**
- Consumes: T1 `PlanItemFormSheet(meeting:item:initialMode:)`;`.fromPlan` 表单;`PlanTodoCard`
- Produces: 备忘剥离卡流;左缘侧签+半屏弹窗;点圈/点卡都开 .fromPlan

- [ ] **Step 1: 备忘剥离**。派生数据区:`let memos = allPlans.filter { $0.day == nil }`;`prepared`/`pendingPlans` 均加 `.filter { $0.day != nil }`(已备组、散插、tail、灰卡从此只含日程)。tail 排序里 nil plannedMoment 分支自然消失(可留,防御)。
- [ ] **Step 2: 侧签+弹窗**。状态加 `@State private var showMemos = false`、`@State private var memoAddSheet = false`;LazyVStack 外层包 ZStack(alignment: .topLeading)(或在既有 body 外 overlay):

```swift
        .overlay(alignment: .topLeading) {
            if showPlans && !memos.isEmpty {
                Button { showMemos = true } label: {
                    Text("备忘 \(memos.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 10).padding(.horizontal, 5)
                        .background(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                                           bottomTrailingRadius: 8, topTrailingRadius: 8)
                            .fill(DS.ink))
                }
                .buttonStyle(DSPressEffect())
                .offset(x: -DS.Spacing.md, y: 4)   // 贴屏幕左缘(抵消父级水平 padding)
            }
        }
```

(注意 TimelineListView 由 MeetingDetailView 包在 ScrollView+padding 里——overlay 挂在 LazyVStack 上会随内容滚走;若需固定,把侧签挂到 MeetingDetailView 的 ScrollView `.overlay(alignment: .leading)` 层。实现时先试挂 TimelineListView 顶层,滚动遮挡问题就上移到 MeetingDetailView——两处都可,以「侧签始终可见不随滚动消失」为验收准绳,MeetingDetailView 方案优先。)
弹窗 sheet:

```swift
        .sheet(isPresented: $showMemos) {
            NavigationStack {
                List {
                    ForEach(memos, id: \.objectID) { item in
                        HStack(spacing: 10) {
                            Button {
                                try? PlanItemRepository(context: context).toggleDone(item)
                                if item.isDone, let id = item.id {
                                    ReminderScheduler.cancel(id: ReminderPlanner.planID(id))
                                }
                            } label: {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(item.isDone ? DS.actionBlue : DS.chipBorder)
                            }
                            .buttonStyle(.plain)
                            Text(item.title ?? "")
                                .strikethrough(item.isDone, color: DS.inkMuted)
                                .foregroundStyle(item.isDone ? DS.inkMuted : DS.ink)
                            if let note = item.note, !note.isEmpty { Text(note).dsFootnote() }
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                let id = item.id
                                try? PlanItemRepository(context: context).delete(item)
                                if let id { ReminderScheduler.cancelPlans([id]) }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .navigationTitle("备忘")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { showMemos = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("＋ 加备忘") { memoAddSheet = true }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .sheet(isPresented: $memoAddSheet) {
                PlanItemFormSheet(meeting: meeting, item: nil, initialMode: .memo)
            }
        }
```

(弹窗里备忘勾选=纯划线,永不转化——正是与待办卡的本质区别。系统 List swipeActions 这里可用:sheet 内无自绘 SwipeDeleteRow 的共存问题,样式从简。)
- [ ] **Step 3: 划掉即弹表单**。`planRow` 里 `PlanTodoCard(item:state:onToggle:)` 的 onToggle 改 `selecting ? nil : { editingPlan = item }`;`.todo` 的 onTapGesture 分支已是 `editingPlan = item` 保持;删除 `convert(_:)` 函数(无调用方)。
- [ ] **Step 4: 「＋ 加个待办」**。sheet 改 `PlanItemFormSheet(meeting: meeting, item: nil, initialMode: .schedule)`(备忘入口在侧签弹窗里,这里保持日程直达)。
- [ ] **Step 5: 门禁** → **Step 6: Commit**:`反馈⑨T4:时间线——备忘剥离进左缘侧签弹窗(永不转化),待办点圈点卡都弹补全表单`

---

### Task 5: 删除 convertToMoment + 测试调整

**Files:** Modify: `Persistence/PlanItemRepository.swift`、`Tests/PlanConversionTests.swift`

**Interfaces:** Consumes: T4 已删唯一调用方。Produces: repo 只剩 `plannedMoment`;测试只留合成/映射用例

- [ ] **Step 1**: 删 `convertToMoment(_:now:)` 整个方法(`plannedMoment` 保留)。
- [ ] **Step 2**: `Tests/PlanConversionTests.swift` 删 testConvertMapsFields/testConvertClampsFutureToNow/testConvertMemoWithoutDate/testConvertResolvesPlaceText/testConvertAllDayUsesNow 五个用例及其专属辅助;保留 testPlannedMomentComposition 与 testMomentTypeMappingCoversAllCategories(fromPlan 预填仍用这两套逻辑)。文件头注释更新:转化唯一入口=MomentFormView .fromPlan(反馈⑨ 2A),端到端由 UI 用例锁。
- [ ] **Step 3: 门禁**(单元数会降,全绿即可)→ **Step 4: Commit**:`反馈⑨T5:删 convertToMoment 死码——转化唯一入口收敛为 .fromPlan 表单,留时刻合成与类目映射单测`

---

### Task 6: 小本本新壳

**Files:** Modify: `Features/Ledger/LedgerListView.swift`

**Interfaces:** Consumes: LedgerRules/TodoRules/LedgerFilter 不动。Produces: 四 tab 新头部+统一新卡

- [ ] **Step 1: 段枚举改**:

```swift
/// 小本本四段(反馈⑨换壳):好事(praise)/生气(complaint+trigger 两组)/喜好(like)/待办(记得做)
enum LedgerSegment: CaseIterable {
    case praise, angry, likes, todos
    var label: String {
        switch self {
        case .praise: return "好事"
        case .angry: return "生气"
        case .likes: return "喜好"
        case .todos: return "待办"
        }
    }
}
```

调用处适配:今天卡等入口若用 `.todos` 名字不变;`initialSegment` 默认 .praise。全仓 grep `LedgerSegment.`/`.moods`/`.complaint` 引用一并改(如 MainShell/HomeView 里 initialSegment 传参)。
- [ ] **Step 2: 头部重做**。`navigationTitle("小本本")` 改 `.toolbar(.hidden, for: .navigationBar)` 不可取——小本本是 tab 根页,保留导航栏但把标题区自绘:header 改:

```swift
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("小本本").dsPageTitle()
                Spacer()
                Button(selecting ? "完成" : "管理") {
                    selecting.toggle(); selected = []; openSwipeID = nil
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.ink)
                .padding(.vertical, 6).padding(.horizontal, 14)
                .background(Capsule().fill(.white))
                .overlay(Capsule().stroke(DS.hairline, lineWidth: 1))
            }
            HStack(spacing: 6) {
                ForEach(LedgerSegment.allCases, id: \.label) { seg in
                    Button { segment = seg } label: {
                        Text(seg.label)
                            .font(.system(size: 14, weight: segment == seg ? .semibold : .regular))
                            .foregroundStyle(segment == seg ? DS.ink : DS.inkMuted)
                            .padding(.vertical, 7).padding(.horizontal, 14)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(segment == seg ? .white : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(segment == seg ? DS.hairline : .clear, lineWidth: 1))
                    }
                    .buttonStyle(DSPressEffect())
                }
            }
            HStack(spacing: 16) {
                ForEach(LedgerFilter.allCases, id: \.label) { f in
                    Button { filter = f } label: {
                        VStack(spacing: 3) {
                            Text(f.label)
                                .font(.system(size: 12, weight: filter == f ? .semibold : .regular))
                                .foregroundStyle(filter == f ? DS.actionBlue : DS.inkMuted)
                            Rectangle().fill(filter == f ? DS.actionBlue : .clear)
                                .frame(height: 2).clipShape(Capsule())
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(.horizontal, DS.Spacing.md).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.parchment)
    }
```

navigationTitle 置空(`.navigationTitle("")` 或 `.toolbar` 里去管理钮——原 toolbar 管理钮删除);二级筛选**待办段也显示**(删 `if segment != .todos` 包裹)。页面 `.background(DS.parchment)`(原 DS.canvas)。
- [ ] **Step 3: 段内容重组**。body 的 switch:`case .praise: entriesSection(category: .praise)`;`case .angry: angrySection`;`case .likes: entriesSection(category: .like)`;`case .todos: todosSection`。删 moodsSection,新:

```swift
    @ViewBuilder
    private var angrySection: some View {
        let complaints = filtered(categories: [.complaint])
        let triggers = filtered(categories: [.trigger])
        if complaints.isEmpty && triggers.isEmpty {
            emptyHint
        } else {
            if !complaints.isEmpty {
                Text("记一笔").font(.system(size: 13, weight: .bold)).foregroundStyle(DS.inkMuted)
                ForEach(complaints, id: \.objectID) { entry in
                    entryRow(entry) { newCard(entry, icon: "cloud.drizzle") }
                }
            }
            if !triggers.isEmpty {
                Text("⚡ 雷区").font(.system(size: 13, weight: .bold)).foregroundStyle(DS.inkMuted).padding(.top, 4)
                ForEach(triggers, id: \.objectID) { entry in
                    entryRow(entry) { newCard(entry, icon: "bolt") }
                }
            }
        }
    }
```

`entriesSection` 卡片调用改 `newCard(entry, icon: category == .praise ? "heart" : "star")`(praise=heart,like=star)。
- [ ] **Step 4: 统一新卡**。entryCard/moodCard 替换为:

```swift
    /// 反馈⑨新卡:白底大圆角+左圆底图标+标题/详情/脚注(用户设计图版式,米色系)
    private func newCard(_ entry: CDLedgerEntry, icon: String) -> some View {
        let thumb = LedgerRepository(context: context).evidencesSorted(entry).first?.thumbnailData
        return HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(DS.parchment).frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(DS.ink)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.title ?? "").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.ink).lineLimit(1)
                    Spacer()
                    if !LedgerRules.isRevealed(visibilityRaw: entry.visibilityRaw, revealedAt: entry.revealedAt) {
                        Text("🔒").font(.system(size: 10))
                    }
                }
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 12)).foregroundStyle(DS.inkMuted).lineLimit(2)
                }
                HStack(spacing: 8) {
                    Text(metaLine(entry)).dsFootnote()
                    Spacer()
                    if let thumb, let ui = UIImage(data: thumb) {
                        Image(uiImage: ui).resizable().scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.hairline, lineWidth: 1))
        .contentShape(Rectangle())
    }
```

- [ ] **Step 5: 待办段平列表+筛选**。todosSection:visible 计算后追加 author 筛选 `LedgerRules.matches(filter:…)` 同口径(用 `filter`/`authorPartnerID`/`myID`/`visibilityRaw`/`revealedAt`——直接复用 LedgerRules.matches);去掉 mine/theirs 分组,合成一个 `sorted`(TodoRules.sortKey)平列表;todoRow 卡样式改成同 newCard 外观(白卡+描边+圈占图标位),todoMeta 尾部加徽标文案:`parts.append(todo.assigneePartnerID == myID ? "我做" : "Ta做")`。
- [ ] **Step 6: 门禁+全 UI**(testHerPageLook/testRound6Look 等可能截到小本本——断言失败才处理)→ **Step 7: Commit**:`反馈⑨T6:小本本新壳——好事|生气|喜好|待办四段+下划线筛选+统一白卡(米色系,规则层零改动)`

---

### Task 7: 测试改造 + 新 UI 用例 + 全量回归

**Files:** Modify: `UITests/MapFilterReproTests.swift`(必要时 `Support/DebugSeeder.swift`)

- [ ] **Step 1: testRound8PlanFlow 改造**:
  - 备忘断言迁移:进行中不再有「接下来 · 还没做」组与「给她妈带特产」「买伴手礼」卡——改为断言左缘侧签 `app.buttons["备忘 2"]` 存在(或 staticTexts,以实际元素为准);tap 侧签 → 断言弹窗里「给她妈带特产」存在 → 关闭。
  - 点圈路径:`app.buttons["划掉 去码头拍日落"]`.tap() → 断言「补全这段回忆」出现(navigationBars 或 staticTexts)→ 点「存储」→ 断言圈消失+staticText 仍在。
  - 结束见面:灰卡断言改用日程项——种子里没有未完成日程留到结束…「去码头拍日落」被转化了;需要一条不动的未完成日程:种子加 `买伴手礼` 改成日程?spec 备忘不变灰卡。调整种子:加一条日程「江边看夜景」(day=今天 time=nil 全天,不在测试里转化)→ 结束后灰卡断言用它。备忘「买伴手礼」结束后仍在侧签(可加断言:结束后侧签仍在)。
- [ ] **Step 2: 新 testRound9Look**:`--seed-map-demo` 启动 → 足迹→上海卡→时间线:S1 侧签截图;开侧签弹窗 S2;去小本本 tab:好事段 S3、待办段 S4 截图;断言:四 tab 文案存在(好事/生气/喜好/待办)、二级筛选「私密」存在、待办段有筛选行。行前备忘紧凑行:planned 见面种子?现种子只有 ongoing——若无 planned 见面,行前页备忘行照片略过(备忘行样式与侧签弹窗行同构,靠侧签截图人工核)。
- [ ] **Step 3: 单跑两用例绿 → 全 UI 套件绿 → ./scripts/test.sh 绿**
- [ ] **Step 4: Commit**:`反馈⑨T7:测试改造(侧签/补全表单断言)+ testRound9Look 新壳截图 + 全量回归`

---

## Self-Review 记录

- spec §一→T1/T3/T4;§二→T4/T5;§三→T2/T3;§四→T6;§五→T7+各任务门禁。
- 接口一致:`PlanFormMode`/`initialMode`(T1 定义,T3/T4 消费);`PlanItemDetailSheet`(T2 定义,T3 消费);`openInMapsNavigation`(T2 定义两处用)。
- 风险提示:侧签固定位置可能需上移 MeetingDetailView(T4 步骤已写两方案与验收准绳);LedgerSegment 改名需全仓 grep 调用处(T6 Step 1 已列);DS 色名/BluePillButtonStyle 参数以真实源码为准。
