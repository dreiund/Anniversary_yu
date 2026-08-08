# 反馈⑥轮实现计划（排卵预测 · 记得做 · 今天卡 · 本地提醒 · 开关统一 · 足迹日历滑动）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地 spec `docs/superpowers/specs/2026-08-08-r6-todo-ovulation-design.md` 全部六节：排卵紫窗+🌸、小本本第四段「记得做」（新实体）、我们页今天卡、本地通知提醒、可见性 Toggle 统一、足迹日历滑动换月。

**Architecture:** 纯函数层（CyclePredictor 排卵扩展、TodoRules、ReminderPlanner）+ 仓库层（TodoRepository、PlanItemRepository 提醒参数）+ 视图改造。新实体 CDTodoItem 与 CDPlanItem.remindAt 为 CloudKit 增量 schema（部署步骤在收尾任务提示，人工执行）。

**Tech Stack:** SwiftUI + Core Data（NSPersistentCloudKitContainer）+ UserNotifications + XCTest。

## Global Constraints

- 最低 iOS 17.0，禁 iOS 18+ API。
- 新建 .swift 后必须 `./scripts/gen.sh`；门禁 `./scripts/build.sh` / `./scripts/test.sh` 打印 ✅ 构建通过 / ✅ 测试通过；SourceKit 诊断是噪音。
- 文案照抄本计划；按钮 ≤6 字无 emoji（行首 📌/👉/🕐/🩷/🌸 是内容符号不是按钮）。
- 唯一行动蓝 DS.actionBlue；新增 `DS.ovulationBg 0xF0E6FA`、`DS.ovulationInk 0x8E44AD` 仅排卵语义。
- EntryVisibility 锁值复用（0 公开 / 1 私密）；raw 语义零改动。
- 日期落库 startOfDay；测试固定 `Date(timeIntervalSince1970:)` + UTC 日历。
- 起始基线 143 项单测 + 5 UI 用例，任何任务不得回归。
- 提交信息中文 + 两行既定 trailer（Co-Authored-By: Claude Fable 5 <noreply@anthropic.com> / Claude-Session: https://claude.ai/code/session_01UkuNQ16cmqL68DJxJSjefA）。

---

### Task 1: Schema 增量（CDTodoItem 实体 + CDPlanItem.remindAt + 关系 + 孤儿清理计入）

**Files:**
- Modify: `Domain/ModelSchema.swift`
- Modify: `Domain/ManagedObjects.swift`
- Modify: `Persistence/PlacePruner.swift`
- Test: `Tests/PlacePrunerTests.swift`（追加）

**Interfaces:**
- Produces: `CDTodoItem`（@NSManaged：id/title/detail/dueAt/assigneePartnerID/authorPartnerID/visibilityRaw/revealedAt/isDone/doneAt/remindAt/createdAt/couple/place）；`CDPlanItem.remindAt: Date?`；`CDPlace.todoItems: NSSet?`；`CDCouple.todos: NSSet?`。

- [ ] **Step 1: ManagedObjects.swift 追加类**（放 CDPlanItem 类之后）：

```swift
@objc(CDTodoItem)
final class CDTodoItem: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var detail: String?
    @NSManaged var dueAt: Date?
    @NSManaged var assigneePartnerID: UUID?
    @NSManaged var authorPartnerID: UUID?
    @NSManaged var visibilityRaw: Int16
    @NSManaged var revealedAt: Date?
    @NSManaged var isDone: Bool
    @NSManaged var doneAt: Date?
    @NSManaged var remindAt: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var couple: CDCouple?
    @NSManaged var place: CDPlace?
}
```
并给 `CDPlanItem` 类加 `@NSManaged var remindAt: Date?`；`CDPlace` 类加 `@NSManaged var todoItems: NSSet?`；`CDCouple` 类加 `@NSManaged var todos: NSSet?`。

- [ ] **Step 2: ModelSchema.swift**——planItem 实体属性表加一行 `attr("remindAt", .dateAttributeType),`；planItem 定义之后加：

```swift
        let todo = entity("CDTodoItem", CDTodoItem.self, [
            attr("id", .UUIDAttributeType),
            attr("title", .stringAttributeType),
            attr("detail", .stringAttributeType),
            attr("dueAt", .dateAttributeType),
            attr("assigneePartnerID", .UUIDAttributeType),
            attr("authorPartnerID", .UUIDAttributeType),
            attr("visibilityRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("revealedAt", .dateAttributeType),
            attr("isDone", .booleanAttributeType, optional: false, defaultValue: false),
            attr("doneAt", .dateAttributeType),
            attr("remindAt", .dateAttributeType),
            attr("createdAt", .dateAttributeType),
        ])
```
关系区加 `oneToMany(couple, "todos", todo, "couple")` 与 `oneToMany(place, "todoItems", todo, "place", cascade: false)`；`model.entities` 数组补 `todo`。

- [ ] **Step 3: PlacePruner 计入 todo 引用**——三行 filter 之后加：

```swift
            let todos = ((place.todoItems as? Set<CDTodoItem>) ?? []).filter { !$0.isDeleted }
```
判空条件改为 `if moments.isEmpty, ledger.isEmpty, plans.isEmpty, todos.isEmpty {`；文件头注释的「记忆/小本本/日程」改为「记忆/小本本/日程/记得做」。

- [ ] **Step 4: 失败测试**（PlacePrunerTests 追加；先跑确认 RED——报缺 CDTodoItem）：

```swift
    // 反馈⑥：记得做引用的地点不清（PlacePruner 计入 todoItems）
    func testPlaceReferencedOnlyByTodoSurvives() throws {
        let place = makePlace("只有记得做引用")
        let todo = CDTodoItem(context: pc.viewContext)
        todo.id = UUID(); todo.title = "买花"; todo.couple = couple; todo.place = place
        try pc.viewContext.save()
        PlacePruner.pruneOrphans(context: pc.viewContext)
        XCTAssertEqual(try placeCount(), 1)
        pc.viewContext.delete(todo)
        try pc.viewContext.save()
        PlacePruner.pruneOrphans(context: pc.viewContext)
        XCTAssertEqual(try placeCount(), 0)
    }
```

- [ ] **Step 5: `./scripts/test.sh` → ✅（144 项）；提交** `git commit -m "反馈⑥ T1 schema 增量：CDTodoItem 实体、CDPlanItem.remindAt、孤儿清理计入记得做"`。

---

### Task 2: TodoRules 纯函数 + TodoRepository（TDD）

**Files:**
- Create: `Features/Ledger/TodoRules.swift`
- Create: `Persistence/TodoRepository.swift`
- Test: `Tests/TodoTests.swift`

**Interfaces:**
- Consumes: T1 的 CDTodoItem；既有 `LedgerRules.isRevealed`、`EntryVisibility`。
- Produces:
```swift
enum TodoRules {
    static func isVisible(authorID: UUID?, myID: UUID?, visibilityRaw: Int16, revealedAt: Date?) -> Bool
    static func canEdit(authorID: UUID?, myID: UUID?) -> Bool                       // 仅作者
    static func canToggleDone(authorID: UUID?, assigneeID: UUID?, myID: UUID?) -> Bool  // 作者或 assignee
    /// 组内排序 key：未完成在前按 dueAt 升序（nil 最后），已完成沉底按 doneAt 降序
    static func sortKey(isDone: Bool, dueAt: Date?, doneAt: Date?) -> (Int, Double)
}
struct TodoRepository {
    let context: NSManagedObjectContext
    @discardableResult
    func create(couple: CDCouple, title: String, detail: String?, dueAt: Date,
                assigneeID: UUID?, authorID: UUID?, visibility: EntryVisibility,
                place: CDPlace?, remindAt: Date?, calendar: Calendar) throws -> CDTodoItem
    func update(_ todo: CDTodoItem, title: String, detail: String?, dueAt: Date,
                assigneeID: UUID?, place: CDPlace?, remindAt: Date?, calendar: Calendar) throws
    func setDone(_ todo: CDTodoItem, done: Bool, at: Date) throws                   // done=false 清 doneAt
    func reveal(_ todo: CDTodoItem, at: Date) throws                                // 一次性，二次调用不改戳
    func delete(_ todo: CDTodoItem) throws                                          // 保存后 PlacePruner
    func todos(couple: CDCouple) -> [CDTodoItem]                                    // createdAt 降序
}
```

- [ ] **Step 1: 失败测试**：

```swift
import XCTest
import CoreData
@testable import Anniversary

final class TodoTests: XCTestCase {
    private var pc: PersistenceController!
    private var couple: CDCouple!
    private var repo: TodoRepository!
    private let me = UUID(), her = UUID()
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func d(_ day: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(day) * 86_400) }

    override func setUpWithError() throws {
        pc = PersistenceController(inMemory: true)
        couple = try CoupleRepository(context: pc.viewContext)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        repo = TodoRepository(context: pc.viewContext)
    }

    func testRulesVisibilityAndPermissions() {
        // 自己的私密恒可见；对方的私密不可见、公开可见
        XCTAssertTrue(TodoRules.isVisible(authorID: me, myID: me, visibilityRaw: 1, revealedAt: nil))
        XCTAssertFalse(TodoRules.isVisible(authorID: her, myID: me, visibilityRaw: 1, revealedAt: nil))
        XCTAssertTrue(TodoRules.isVisible(authorID: her, myID: me, visibilityRaw: 0, revealedAt: nil))
        XCTAssertTrue(TodoRules.isVisible(authorID: her, myID: me, visibilityRaw: 1, revealedAt: d(1)))
        XCTAssertTrue(TodoRules.canEdit(authorID: me, myID: me))
        XCTAssertFalse(TodoRules.canEdit(authorID: her, myID: me))
        XCTAssertTrue(TodoRules.canToggleDone(authorID: her, assigneeID: me, myID: me))   // 我是 assignee
        XCTAssertTrue(TodoRules.canToggleDone(authorID: me, assigneeID: her, myID: me))   // 我是作者
        XCTAssertFalse(TodoRules.canToggleDone(authorID: her, assigneeID: her, myID: me)) // 都不是
    }

    func testSortKeyOrdersOpenByDueThenDoneSinks() {
        let open1 = TodoRules.sortKey(isDone: false, dueAt: d(3), doneAt: nil)
        let open2 = TodoRules.sortKey(isDone: false, dueAt: d(5), doneAt: nil)
        let openNil = TodoRules.sortKey(isDone: false, dueAt: nil, doneAt: nil)
        let done = TodoRules.sortKey(isDone: true, dueAt: d(1), doneAt: d(9))
        XCTAssertTrue(open1 < open2)
        XCTAssertTrue(open2 < openNil)
        XCTAssertTrue(openNil < done)                              // 完成永远沉底
    }

    func testRepositoryCrudDoneReveal() throws {
        let todo = try repo.create(couple: couple, title: "带充电宝", detail: nil, dueAt: d(10),
                                   assigneeID: her, authorID: me, visibility: .privateUntilRevealed,
                                   place: nil, remindAt: nil, calendar: cal)
        XCTAssertEqual(todo.dueAt, cal.startOfDay(for: d(10)))
        XCTAssertEqual(todo.visibilityRaw, 1)
        XCTAssertNotNil(todo.createdAt)
        try repo.setDone(todo, done: true, at: d(11))
        XCTAssertTrue(todo.isDone)
        XCTAssertEqual(todo.doneAt, d(11))
        try repo.setDone(todo, done: false, at: d(12))
        XCTAssertFalse(todo.isDone)
        XCTAssertNil(todo.doneAt)
        try repo.reveal(todo, at: d(11))
        try repo.reveal(todo, at: d(12))
        XCTAssertEqual(todo.revealedAt, d(11))                     // 一次性
        try repo.update(todo, title: "带两个充电宝", detail: "白色那个", dueAt: d(12),
                        assigneeID: me, place: nil, remindAt: d(12), calendar: cal)
        XCTAssertEqual(todo.assigneePartnerID, me)
        XCTAssertEqual(todo.remindAt, d(12))
        try repo.delete(todo)
        XCTAssertTrue(repo.todos(couple: couple).isEmpty)
    }
}
```

- [ ] **Step 2: RED → Step 3: 实现**

`Features/Ledger/TodoRules.swift`：
```swift
import Foundation

/// 记得做规则（spec ⑥ §二）：可见性与小本本同构；编辑删除仅作者；勾选=作者或 assignee
enum TodoRules {
    static func isVisible(authorID: UUID?, myID: UUID?, visibilityRaw: Int16, revealedAt: Date?) -> Bool {
        if authorID == myID { return true }
        return LedgerRules.isRevealed(visibilityRaw: visibilityRaw, revealedAt: revealedAt)
    }

    static func canEdit(authorID: UUID?, myID: UUID?) -> Bool {
        authorID != nil && authorID == myID
    }

    static func canToggleDone(authorID: UUID?, assigneeID: UUID?, myID: UUID?) -> Bool {
        guard myID != nil else { return false }
        return authorID == myID || assigneeID == myID
    }

    /// 未完成在前按 dueAt 升序（nil 最后）；已完成沉底按 doneAt 降序
    static func sortKey(isDone: Bool, dueAt: Date?, doneAt: Date?) -> (Int, Double) {
        if isDone {
            return (1, -(doneAt?.timeIntervalSince1970 ?? 0))
        }
        return (0, dueAt?.timeIntervalSince1970 ?? .greatestFiniteMagnitude)
    }
}
```

`Persistence/TodoRepository.swift`：
```swift
import CoreData

struct TodoRepository {
    let context: NSManagedObjectContext

    @discardableResult
    func create(couple: CDCouple, title: String, detail: String?, dueAt: Date,
                assigneeID: UUID?, authorID: UUID?, visibility: EntryVisibility,
                place: CDPlace?, remindAt: Date?, calendar: Calendar) throws -> CDTodoItem {
        let todo = CDTodoItem(context: context)
        todo.id = UUID()
        todo.title = title
        todo.detail = detail
        todo.dueAt = calendar.startOfDay(for: dueAt)
        todo.assigneePartnerID = assigneeID
        todo.authorPartnerID = authorID
        todo.visibilityRaw = visibility.rawValue
        todo.place = place
        todo.remindAt = remindAt
        todo.createdAt = Date()
        todo.couple = couple
        try context.save()
        return todo
    }

    func update(_ todo: CDTodoItem, title: String, detail: String?, dueAt: Date,
                assigneeID: UUID?, place: CDPlace?, remindAt: Date?, calendar: Calendar) throws {
        todo.title = title
        todo.detail = detail
        todo.dueAt = calendar.startOfDay(for: dueAt)
        todo.assigneePartnerID = assigneeID
        todo.place = place
        todo.remindAt = remindAt
        try context.save()
    }

    func setDone(_ todo: CDTodoItem, done: Bool, at: Date) throws {
        todo.isDone = done
        todo.doneAt = done ? at : nil
        try context.save()
    }

    /// 公开仪式：一次性置戳（同小本本 reveal 语义），不碰 visibilityRaw
    func reveal(_ todo: CDTodoItem, at: Date) throws {
        guard todo.revealedAt == nil else { return }
        todo.revealedAt = at
        try context.save()
    }

    func delete(_ todo: CDTodoItem) throws {
        context.delete(todo)
        try context.save()
        PlacePruner.pruneOrphans(context: context)
    }

    func todos(couple: CDCouple) -> [CDTodoItem] {
        ((couple.todos as? Set<CDTodoItem>) ?? [])
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
}
```

- [ ] **Step 4: `./scripts/gen.sh && ./scripts/test.sh` → ✅（147 项）；提交** `git commit -m "反馈⑥ T2 记得做规则与仓库：可见性/权限/排序、CRUD/勾选/一次性公开"`。

---

### Task 3: CyclePredictor 排卵扩展（TDD）

**Files:**
- Modify: `Domain/CyclePredictor.swift`
- Test: `Tests/CyclePredictorTests.swift`（追加）

**Interfaces:**
- Produces:
```swift
struct OvulationWindow: Equatable {
    let ovulationDay: Date            // 🌸 那天（startOfDay）
    let days: [Date]                  // 前 5 后 4 共 10 天（startOfDay）
}
extension CyclePredictor {
    /// 每个「下一次开始日」产出一窗：历史=后一段实际开始日；未来=nextStarts 逐个（1A 定稿）
    static func ovulationWindows(cycles: [(start: Date, end: Date?)],
                                 nextStarts: [Date], calendar: Calendar) -> [OvulationWindow]
}
```

- [ ] **Step 1: 失败测试**（CyclePredictorTests 追加）：

```swift
    func testOvulationWindowsFromHistoryAndPredictions() {
        // 历史两段（开始 d0、d28）→ 历史窗 1 个（依据 d28）：排卵日 d14，days d9…d18
        // nextStarts [d56] → 未来窗 1 个：排卵日 d42，days d37…d46
        let windows = CyclePredictor.ovulationWindows(
            cycles: [(d(0), d(5)), (d(28), d(33))],
            nextStarts: [d(56)], calendar: cal)
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].ovulationDay, d(14))
        XCTAssertEqual(windows[0].days.first, d(9))
        XCTAssertEqual(windows[0].days.count, 10)
        XCTAssertEqual(windows[0].days.last, d(18))
        XCTAssertEqual(windows[1].ovulationDay, d(42))
    }

    func testOvulationWindowsSingleCycleUsesPredictionsOnly() {
        let windows = CyclePredictor.ovulationWindows(
            cycles: [(d(0), nil)], nextStarts: [d(28), d(56), d(84)], calendar: cal)
        XCTAssertEqual(windows.count, 3)                           // 无相邻历史对，只有预测窗
        XCTAssertEqual(windows[0].ovulationDay, d(14))
    }
```

- [ ] **Step 2: RED → Step 3: 实现**（CyclePredictor.swift 末尾追加）：

```swift
struct OvulationWindow: Equatable {
    let ovulationDay: Date
    let days: [Date]
}

extension CyclePredictor {
    /// 排卵窗（反馈⑥ 1A）：排卵日=「下一次开始日」−14 天；窗=前 5 后 4 共 10 天。
    /// 历史区间回填（相邻两段中后一段的实际开始日）+ 未来预测（nextStarts 逐个）。
    static func ovulationWindows(cycles: [(start: Date, end: Date?)],
                                 nextStarts: [Date], calendar: Calendar) -> [OvulationWindow] {
        let sortedStarts = cycles.map { calendar.startOfDay(for: $0.start) }.sorted()
        let anchors = Array(sortedStarts.dropFirst()) + nextStarts.map { calendar.startOfDay(for: $0) }
        return anchors.compactMap { nextStart in
            guard let ovulation = calendar.date(byAdding: .day, value: -14, to: nextStart) else { return nil }
            let days = (-5...4).compactMap { calendar.date(byAdding: .day, value: $0, to: ovulation) }
            return OvulationWindow(ovulationDay: ovulation, days: days)
        }
    }
}
```

- [ ] **Step 4: `./scripts/test.sh` → ✅（149 项）；提交** `git commit -m "反馈⑥ T3 排卵窗纯函数：−14 天规则、前5后4、历史回填+预测"`。

---

### Task 4: 可见性统一改「私密」Toggle（互评 + 喜怒）

**Files:**
- Modify: `Features/Ledger/LedgerFormView.swift`（visibilityChip 两处调用与函数、footnote 文案）
- Modify: `Features/Ledger/QuickLedgerSheet.swift`（同上）

**Interfaces:**
- Consumes: 既有 `@State visibility: EntryVisibility`、`visibilityLocked`。
- Produces: 两表单的可见性控件统一为 Toggle；供 T8 的 TodoFormView 照抄同款。

- [ ] **Step 1: 两个文件同改**——把 `visibilityChip("公开", .sharedImmediately)` / `visibilityChip("🔒 私密", .privateUntilRevealed)` 两行（及其外层容器里仅剩的排布）替换为：

```swift
                    Toggle("私密", isOn: Binding(
                        get: { visibility == .privateUntilRevealed },
                        set: { visibility = $0 ? .privateUntilRevealed : .sharedImmediately }))
                        .disabled(visibilityLocked)
```
footnote 两态文案改为：
```swift
                    Text(visibilityLocked
                         ? "已公开，不可改回私密"
                         : "开着=公开前只有你看得到")
```
`private func visibilityChip(...)` 整个函数删除（两文件各自）。保持既有「编辑中把私密关掉=公开仪式弹确认」路径不动（若该逻辑挂在 chips 点击上，迁到 Binding 的 set 里同语义触发；照原文件现状最小迁移）。

- [ ] **Step 2: `./scripts/build.sh && ./scripts/test.sh` → ✅✅；提交** `git commit -m "反馈⑥ T4 可见性统一开关：互评/喜怒改「私密」Toggle，锁定态置灰"`。

---

### Task 5: ReminderPlanner + 排程接线基件（TDD）

**Files:**
- Create: `Support/ReminderScheduler.swift`
- Modify: `Persistence/PlanItemRepository.swift`（add/update 增 remindAt 参数）
- Test: `Tests/ReminderPlannerTests.swift`

**Interfaces:**
- Produces:
```swift
/// 纯函数部分（可测）：通知 id 与内容组装
enum ReminderPlanner {
    static func todoID(_ id: UUID) -> String            // "todo-<uuid>"
    static func planID(_ id: UUID) -> String            // "plan-<uuid>"
    static func shouldSchedule(remindAt: Date?, now: Date) -> Bool   // 非空且在未来
}
/// UN 排程（薄壳，不测）：schedule(id:title:body:at:) / cancel(id:)
enum ReminderScheduler {
    static func schedule(id: String, title: String, body: String, at date: Date)
    static func cancel(id: String)
}
```
- PlanItemRepository：`add(to:day:time:title:note:placeText:authorID:remindAt:)`（新参默认 nil）、`update(_:day:time:title:note:placeText:remindAt:)`（新参默认 nil 表「不改」？——**不用默认**，update 全量写 `item.remindAt = remindAt`，调用方传现值）。

- [ ] **Step 1: 失败测试**：

```swift
import XCTest
@testable import Anniversary

final class ReminderPlannerTests: XCTestCase {
    func testIDs() {
        let u = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        XCTAssertEqual(ReminderPlanner.todoID(u), "todo-11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(ReminderPlanner.planID(u), "plan-11111111-2222-3333-4444-555555555555")
    }
    func testShouldSchedule() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(ReminderPlanner.shouldSchedule(remindAt: nil, now: now))
        XCTAssertFalse(ReminderPlanner.shouldSchedule(remindAt: Date(timeIntervalSince1970: 999), now: now))
        XCTAssertTrue(ReminderPlanner.shouldSchedule(remindAt: Date(timeIntervalSince1970: 1_001), now: now))
    }
}
```
另在 `Tests/MeetingEditTests.swift` 的批量测试后追加一条：
```swift
    func testPlanItemRemindAtPersists() throws {
        let (pc, couple) = try makeCouple()
        let meetings = MeetingRepository(context: pc.viewContext)
        let m = try meetings.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        let plans = PlanItemRepository(context: pc.viewContext)
        let item = try plans.add(to: m, day: nil, time: nil, title: "买票", note: nil,
                                 placeText: nil, authorID: nil, remindAt: Date(timeIntervalSince1970: 500))
        XCTAssertEqual(item.remindAt, Date(timeIntervalSince1970: 500))
        try plans.update(item, day: nil, time: nil, title: "买票", note: nil, placeText: nil, remindAt: nil)
        XCTAssertNil(item.remindAt)
    }
```

- [ ] **Step 2: RED → Step 3: 实现**

`Support/ReminderScheduler.swift`：
```swift
import UserNotifications

/// 本地提醒（spec ⑥ §五）：排程/取消都发生在操作设备；标题=事项主题。
enum ReminderPlanner {
    static func todoID(_ id: UUID) -> String { "todo-\(id.uuidString.lowercased())" }
    static func planID(_ id: UUID) -> String { "plan-\(id.uuidString.lowercased())" }
    static func shouldSchedule(remindAt: Date?, now: Date) -> Bool {
        guard let remindAt else { return false }
        return remindAt > now
    }
}

enum ReminderScheduler {
    static func schedule(id: String, title: String, body: String, at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.removePendingNotificationRequests(withIdentifiers: [id])
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    static func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
```
PlanItemRepository：`add` 签名尾插 `remindAt: Date? = nil`，赋 `item.remindAt = remindAt`；`update` 签名尾插 `remindAt: Date?`，赋 `item.remindAt = remindAt`（既有调用点 PlanItemFormSheet 编译会断——同步补传现值 `remindAt: item?.remindAt ?? nil` 占位，T10 再接真 UI）。

- [ ] **Step 4: `./scripts/gen.sh && ./scripts/test.sh` → ✅（152 项）；提交** `git commit -m "反馈⑥ T5 提醒基件：ReminderPlanner 纯函数、UN 排程薄壳、行前日程 remindAt 参数"`。

---

### Task 6: 紫窗上双日历（她月历 + 足迹日历）+ DS 双色

**Files:**
- Modify: `DesignSystem/DS.swift`（roseCell 行后加两色）
- Modify: `Features/Her/CycleMonthGrid.swift`（CycleDayMarks 加字段、cell 紫底+🌸）
- Modify: `Features/Her/HerView.swift`（marks 注入排卵窗、图例追加）
- Modify: `Features/Calendar/CalendarView.swift`（紫底/🌸 注入 CalendarDayCell）
- Modify: `Features/Settings/SettingsView.swift`（开关文案改「足迹日历周期底色」）

**Interfaces:**
- Consumes: T3 `CyclePredictor.ovulationWindows`。
- Produces: `CycleDayMarks` 增 `var ovulation = false`、`var isOvulationDay = false`；`CalendarDayCell` 增 `var isOvulationDay: Bool = false`（既有 `isCycleDay` 旁）。

- [ ] **Step 1: DS 两色**：
```swift
    static let ovulationBg = Color(hex: 0xF0E6FA)   // 排卵期淡紫底（反馈⑥）
    static let ovulationInk = Color(hex: 0x8E44AD)  // 排卵期紫字（反馈⑥）
```
- [ ] **Step 2: CycleMonthGrid**——CycleDayMarks 加两字段；cell：
  - 背景优先级改为：`inPeriod` 浅粉 → else `ovulation` 紫底 `RoundedRectangle(cornerRadius: 9).fill(DS.ovulationBg)` → else `predicted` 虚线；
  - 数字颜色：`m.inPeriod || m.predicted ? DS.roseCycle : (m.ovulation ? DS.ovulationInk : DS.ink)`；
  - 🌸：数字与四点行之间插 `if m.isOvulationDay { Text("🌸").font(.system(size: 7)) }`（cell 高度 44 不变，四点行照旧）。
- [ ] **Step 3: HerView.marks**——预测循环之后追加：
```swift
        for window in CyclePredictor.ovulationWindows(cycles: inputs,
                                                      nextStarts: prediction.nextStarts,
                                                      calendar: cal) {
            for day in window.days where interval.contains(day) {
                if result[day]?.inPeriod != true {
                    result[day, default: CycleDayMarks()].ovulation = true
                }
            }
            if interval.contains(window.ovulationDay), result[window.ovulationDay]?.inPeriod != true {
                result[window.ovulationDay, default: CycleDayMarks()].isOvulationDay = true
            }
        }
```
图例第一行末尾追加 `· 紫=排卵期`（数据积累中追加语照旧在其后）。
- [ ] **Step 4: CalendarView**——已有周期天 Set 构造旁，同样用 `ovulationWindows` 构造 `ovulationDays: Set<Date>` 与 `ovulationFlowerDays: Set<Date>`（同受 `cycleTintOn` 开关控制）；`CalendarDayCell` 加 `var isOvulationDay: Bool = false` 与 `var isOvulationFlower: Bool = false`？——**只加两个 Bool**：`isOvulationDay`（紫底）与 `isOvulationFlower`（🌸）。背景 ZStack 里 roseCell 分支后加 `else if isOvulationDay { RoundedRectangle(cornerRadius: 8).fill(DS.ovulationBg) }`（经期红优先）；🌸 放在格内既有内容底部 `if isOvulationFlower { Text("🌸").font(.system(size: 6)) }`（与 dTag overlay 不冲突则放 VStack 尾）。调用点传参。
- [ ] **Step 5: SettingsView**——`Toggle("足迹日历经期底色", ...)` 文案改 `Toggle("足迹日历周期底色", ...)`（键不动）。
- [ ] **Step 6: `./scripts/build.sh && ./scripts/test.sh` → ✅✅；提交** `git commit -m "反馈⑥ T6 排卵紫窗上双日历：淡紫底+🌸、红优先、图例与开关改名"`。

---

### Task 7: 足迹日历滑动换月

**Files:**
- Modify: `Features/Calendar/CalendarView.swift`

**Interfaces:**
- Consumes: 既有 `monthAnchor` 状态、`CalendarProjector.cells/summary`、‹ › 步进钮、回今天。
- Produces: 月份区域 TabView(.page) 分页（偏移 -24…12），滑动与 ‹ ›/回今天 同步。

- [ ] **Step 1: 状态改造**——`monthAnchor` 改为派生：`@State private var monthOffset = 0`，`private var monthAnchor: Date { cal.date(byAdding: .month, value: monthOffset, to: cal.startOfDay(for: Date())) ?? Date() }`（原 `monthAnchor = ...` 赋值处：回今天 → `monthOffset = 0`；‹ › → `monthOffset ∓/± 1`，clamp -24…12）。
- [ ] **Step 2: 网格区包 TabView**——照 HerView.calendarCard 的样板：
```swift
            TabView(selection: $monthOffset) {
                ForEach(-24...12, id: \.self) { offset in
                    let anchor = cal.date(byAdding: .month, value: offset, to: cal.startOfDay(for: Date())) ?? Date()
                    monthGrid(anchor: anchor)          // 既有格子渲染抽成带 anchor 参数的方法
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: <既有网格高度，按现行行数计算或固定值>)
```
既有 cells/summary 计算全部改为吃传入 anchor（`cells(for: anchor)`）。月历下方小结卡（约会日模式）保持当前月（用 monthAnchor 派生值）。
- [ ] **Step 3: `./scripts/build.sh && ./scripts/test.sh` → ✅✅（UI 用例 testSwitchToEmptyCategory 等不受影响——日历不在其路径）；提交** `git commit -m "反馈⑥ T7 足迹日历滑动换月：TabView 分页与 ‹›/回今天 同步"`。

注：`frame(height:)` 的具体值以现行网格实际高度为准（6 行月 ≈ 44×6+星期行+边距）；实现时先量 ScrollView 内现值，不得让格子被裁。

---

### Task 8: TodoFormView + ⊕ 面板替换

**Files:**
- Create: `Features/Ledger/TodoFormView.swift`
- Modify: `App/ActionPanel.swift`（亲密格 → 记得做）
- Modify: `App/MainShell.swift`（PanelAction/ShellSheet 对应改）

**Interfaces:**
- Consumes: T2 TodoRepository/TodoRules、T5 ReminderPlanner/Scheduler、T4 的 Toggle 私密样式、既有 PlacePickerSheet/PlaceResolver（照 LedgerFormView 的地点行搬）、CoupleRepository.currentPartnerID/otherPartner。
- Produces: `TodoFormMode { case create(CDCouple); case edit(CDTodoItem) }`、`struct TodoFormView: View`；PanelAction `.intimacy` 改名 `.todo`（MainShell handle 打开 `.sheet .todoForm`）。

- [ ] **Step 1: TodoFormView 实现**（结构照 QuickLedgerSheet 的 NavigationStack+GroupedSection 模式）：
  - 顶部分段 `Ta做 | 我做`（`@State assigneeIsMe = false`，默认 Ta做）；
  - 行：标题 TextField `要做什么`（必填，空则保存禁用）、详情 TextField `详情（可选）`、`目标日` DatePicker(date，默认今天)、地点行（照 LedgerFormView 地点行原样搬：选地点 ›/已选名/清除）、`私密` Toggle（T4 同款 + footnote 两态 + visibilityLocked 逻辑：编辑已公开条目时置灰；编辑私密条目关 Toggle 弹确认 `公开给 TA？`/`公开后 TA 会看到这条，且不可撤回。`确认=保存时调 reveal 等效——照 LedgerFormView 现行等效公开路径搬）；
  - `提醒我` Toggle + 展开 `提醒时刻` DatePicker(date+time，默认目标日 09:00)，footnote `提醒只响在设置它的手机上`；
  - 保存：create → `repo.create(...)`；edit → `repo.update(...)`；保存后排程/取消：
```swift
        if let id = savedTodo.id {
            let key = ReminderPlanner.todoID(id)
            if remindOn, ReminderPlanner.shouldSchedule(remindAt: remindDate, now: Date()) {
                ReminderScheduler.schedule(id: key, title: title,
                                           body: detail.isEmpty ? "记得做" : detail, at: remindDate)
            } else {
                ReminderScheduler.cancel(id: key)
            }
        }
```
  - assignee 解析：`assigneeIsMe ? myID : otherID`（couple 从 mode 取；otherID = CoupleRepository.otherPartner(of:)?.id）；
  - 编辑模式底部红字 `删除这条` → 确认 `删除这条记得做？` → `repo.delete` + `ReminderScheduler.cancel` + dismiss。
- [ ] **Step 2: ActionPanel**——`case intimacy` 改 `case todo`；亲密 Tile 换 `Tile(symbol: "checkmark.circle", title: "记得做", action: .todo)`（经期格照旧）。MainShell：`handle` 的 `.intimacy` 分支删（其 segment 逻辑并入 `.cycle` 保持经期直达）、加 `.todo` → `activeSheet = .todoForm`；ShellSheet 加 `case todoForm`（id "todoForm"），sheet switch 给 `TodoFormView(mode: .create(couple))`（couple 取法照 `.ledgerForm` 分支）。cycleDay 的 intimacy 预选段能力保留（她页日历还用）。
- [ ] **Step 3: `./scripts/gen.sh && ./scripts/build.sh && ./scripts/test.sh` → ✅✅；提交** `git commit -m "反馈⑥ T8 记得做表单与 ⊕ 替换：Ta做|我做、私密开关、提醒行、亲密格退位"`。

---

### Task 9: 小本本第四段「记得做」列表

**Files:**
- Modify: `Features/Ledger/LedgerListView.swift`

**Interfaces:**
- Consumes: T2 全部、T8 TodoFormView（编辑入口）。
- Produces: `LedgerSegment` 加 `case todos`（label `记得做`）；`LedgerListView(initialSegment: LedgerSegment = .praise)`（新 init 参数，`_segment = State(initialValue: initialSegment)`）。

- [ ] **Step 1: 段与筛选**——LedgerSegment 加 `case todos`（CaseIterable 自动进 chips 行）；header 里筛选行包 `if segment != .todos { ... }`（记得做段不套四档筛选）。
- [ ] **Step 2: todosSection**（body 的 switch 加分支）：

```swift
    @ViewBuilder
    private var todosSection: some View {
        let repo = TodoRepository(context: context)
        let all = couples.first.map { repo.todos(couple: $0) } ?? []
        let visible = all.filter {
            TodoRules.isVisible(authorID: $0.authorPartnerID, myID: myID,
                                visibilityRaw: $0.visibilityRaw, revealedAt: $0.revealedAt)
        }
        let mine = visible.filter { $0.assigneePartnerID == myID }
            .sorted { TodoRules.sortKey(isDone: $0.isDone, dueAt: $0.dueAt, doneAt: $0.doneAt)
                    < TodoRules.sortKey(isDone: $1.isDone, dueAt: $1.dueAt, doneAt: $1.doneAt) }
        let theirs = visible.filter { $0.assigneePartnerID != myID }
            .sorted { TodoRules.sortKey(isDone: $0.isDone, dueAt: $0.dueAt, doneAt: $0.doneAt)
                    < TodoRules.sortKey(isDone: $1.isDone, dueAt: $1.dueAt, doneAt: $1.doneAt) }
        if mine.isEmpty && theirs.isEmpty {
            emptyHint
        } else {
            if !mine.isEmpty {
                Text("📌 我做").font(.system(size: 14, weight: .bold))
                ForEach(mine, id: \.objectID) { todoRow($0) }
            }
            if !theirs.isEmpty {
                Text("👉 Ta做").font(.system(size: 14, weight: .bold)).padding(.top, 4)
                ForEach(theirs, id: \.objectID) { todoRow($0) }
            }
        }
    }
```
- [ ] **Step 3: todoRow**——勾选圈 + 内容 + 左滑删（作者），点行→作者编辑/非作者只读详情：

```swift
    @ViewBuilder
    private func todoRow(_ todo: CDTodoItem) -> some View {
        let canEdit = TodoRules.canEdit(authorID: todo.authorPartnerID, myID: myID)
        let row = HStack(spacing: 10) {
            Button {
                if TodoRules.canToggleDone(authorID: todo.authorPartnerID,
                                           assigneeID: todo.assigneePartnerID, myID: myID) {
                    try? TodoRepository(context: context).setDone(todo, done: !todo.isDone, at: Date())
                    if todo.isDone, let id = todo.id {
                        ReminderScheduler.cancel(id: ReminderPlanner.todoID(id))   // 完成即取消提醒
                    }
                }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(todo.isDone ? DS.actionBlue : DS.chipBorder)
            }
            .buttonStyle(DSPressEffect())
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(todo.isDone ? DS.inkMuted : DS.ink)
                    .strikethrough(todo.isDone, color: DS.inkMuted)
                Text(todoMeta(todo)).dsFootnote()
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment))
        .contentShape(Rectangle())
        .onTapGesture {
            if canEdit { editingTodo = todo } else { viewingTodo = todo }
        }
        if canEdit {
            SwipeDeleteRow(id: todo.objectID, openID: $openSwipeID) { pendingDeleteTodo = todo }
                content: { row }
        } else {
            row
        }
    }

    private func todoMeta(_ todo: CDTodoItem) -> String {
        var parts: [String] = []
        if let due = todo.dueAt { parts.append(Fmt.monthDay.string(from: due)) }
        if !LedgerRules.isRevealed(visibilityRaw: todo.visibilityRaw, revealedAt: todo.revealedAt) {
            parts.append("🔒")
        }
        if todo.isDone { parts.append("已完成") }
        return parts.joined(separator: " · ")
    }
```
状态：`@State editingTodo: CDTodoItem?`（sheet → `TodoFormView(mode: .edit($0))`）、`@State viewingTodo: CDTodoItem?`（只读详情 sheet：字段全览 + assignee 可用的大钮 `完成`/`取消完成`，照 GroupedSection 行式排布）、`@State pendingDeleteTodo: CDTodoItem?`（确认 `删除这条记得做？` → repo.delete + cancel 提醒）。`let _ =` 刷新注册加一个 `@FetchRequest CDTodoItem` count。init 参数：`init(initialSegment: LedgerSegment = .praise) { _segment = State(initialValue: initialSegment) }`（既有 @State segment 声明改 init 赋值式）。
- [ ] **Step 4: `./scripts/build.sh && ./scripts/test.sh` → ✅✅；提交** `git commit -m "反馈⑥ T9 小本本第四段：我做/Ta做分组、勾选沉底、作者左滑删、只读详情"`。

---

### Task 10: 我们页「今天」卡 + 行前表单提醒行

**Files:**
- Modify: `Features/Home/HomeView.swift`（今天卡 + 提醒区经期行移除）
- Modify: `Features/Plan/PlanItemFormSheet.swift`（提醒行 + 保存排程）

**Interfaces:**
- Consumes: T2/T5/T9（LedgerListView(initialSegment:)）、既有 PlanItemRepository（T5 已带 remindAt 参数）、CycleRepository/CyclePredictor（提醒区现行取数样板 HomeView:200-232）。
- Produces: HomeView 新 `todayCard(couple:)`。

- [ ] **Step 1: 今天卡**（提醒区 `Text("提醒").dsSectionTitle()` 之前插入；spec §四文案照抄）：

```swift
    @ViewBuilder
    private func todayCard(_ couple: CDCouple) -> some View {
        let today = Calendar.current.startOfDay(for: Date())
        let planRows: [(CDMeeting, CDPlanItem)] = meetings
            .filter { $0.statusRaw != MeetingStatus.finished.rawValue }
            .flatMap { meeting in
                (((meeting.planItems as? Set<CDPlanItem>) ?? []))
                    .filter { $0.day.map { Calendar.current.isDate($0, inSameDayAs: today) } ?? false }
                    .sorted { ($0.time ?? .distantFuture) < ($1.time ?? .distantFuture) }
                    .map { (meeting, $0) }
            }
        let cycleRepo = CycleRepository(context: context)
        let cycleInputs = cycleRepo.cyclesSorted(couple: couple).compactMap { c -> (start: Date, end: Date?)? in
            c.startDate.map { ($0, c.endDate) }
        }
        let cycleOngoing = cycleRepo.ongoing(couple: couple)
        let cycleDelay = cycleInputs.isEmpty ? nil
            : CyclePredictor.predict(cycles: cycleInputs, calendar: .current).nextStarts.first.flatMap {
                CyclePredictor.delayDays(nextStart: $0, hasOngoing: cycleOngoing != nil,
                                         today: Date(), calendar: .current)
            }
        let myID = CoupleRepository(context: context).currentPartnerID(of: couple)
        let dueTodos = TodoRepository(context: context).todos(couple: couple).filter {
            !$0.isDone
            && ($0.dueAt.map { Calendar.current.isDate($0, inSameDayAs: today) } ?? false)
            && TodoRules.isVisible(authorID: $0.authorPartnerID, myID: myID,
                                   visibilityRaw: $0.visibilityRaw, revealedAt: $0.revealedAt)
        }
        let visiblePlanRows = Array(planRows.prefix(3))
        if !planRows.isEmpty || cycleOngoing != nil || cycleDelay != nil || !dueTodos.isEmpty {
            DarkCard {
                VStack(alignment: .leading, spacing: 7) {
                    Text("今天 · \(Fmt.monthDayWeek.string(from: Date()))")
                        .font(.system(size: 12)).foregroundStyle(DS.onDarkMuted)
                    ForEach(Array(visiblePlanRows.enumerated()), id: \.offset) { _, pair in
                        todayRow(icon: "🕐",
                                 text: "\(pair.1.time.map { Fmt.hm.string(from: $0) } ?? "全天") \(pair.1.title ?? "")",
                                 link: "行前 ›") { PlanView(meeting: pair.0) }
                    }
                    if planRows.count > 3 {
                        Text("还有 \(planRows.count - 3) 条")
                            .font(.system(size: 12)).foregroundStyle(DS.onDarkMuted)
                    }
                    if let cycleDelay {
                        todayRow(icon: "🕐", text: "已推迟 \(cycleDelay) 天", link: "她 ›") { HerView() }
                    } else if let cycleOngoing, let start = cycleOngoing.startDate {
                        let n = (Calendar.current.dateComponents([.day], from: start, to: today).day ?? 0) + 1
                        todayRow(icon: "🩷", text: "经期第 \(n) 天", link: "她 ›") { HerView() }
                    }
                    ForEach(dueTodos, id: \.objectID) { todo in
                        todayRow(icon: todo.assigneePartnerID == myID ? "📌" : "👉",
                                 text: todo.title ?? "", link: "记得做 ›") {
                            LedgerListView(initialSegment: .todos)
                        }
                    }
                }
            }
        }
    }

    private func todayRow<D: View>(icon: String, text: String, link: String,
                                   @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination() } label: {
            HStack {
                Text("\(icon) \(text)").font(.system(size: 15)).foregroundStyle(.white)
                Spacer()
                Text(link).font(.system(size: 12)).foregroundStyle(DS.skyBlue)
            }
        }
        .buttonStyle(.plain)
    }
```
调用点：body 里提醒区（`reminders(couple)`）之前插 `todayCard(couple)`。**提醒区经期两行移除**：`reminders(_:)` 里删掉 `cycleDelay`/`cycleOngoing` 两个行分支与其取数（空态判断退回 `stale == nil && pendingEvals.isEmpty`）——今天卡接管（spec §四）。
- [ ] **Step 2: PlanItemFormSheet 提醒行**——「指定时间」Toggle 组之后加：

```swift
                        Toggle("提醒我", isOn: $remindOn.animation())
                            .padding(.horizontal, 14).padding(.vertical, 6)
                        if remindOn {
                            DatePicker("提醒时刻", selection: $remindDate)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                            Text("提醒只响在设置它的手机上").dsFootnote()
                                .padding(.horizontal, 14).padding(.bottom, 6)
                        }
```
状态 `@State remindOn = false`、`@State remindDate = Date()`；编辑模式载入 `item.remindAt`（非空→remindOn true）；`hasDay` 的日期变化时若 remindDate 未手动动过默认 `该日 09:00`（简化：remindOn 打开瞬间设默认 `cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? Date()`）。保存路径：add/update 传 `remindAt: remindOn ? remindDate : nil`；保存成功后：
```swift
        if let id = item.id {
            let key = ReminderPlanner.planID(id)
            if remindOn, ReminderPlanner.shouldSchedule(remindAt: remindDate, now: Date()) {
                ReminderScheduler.schedule(id: key, title: titleText,
                                           body: "行前日程", at: remindDate)
            } else {
                ReminderScheduler.cancel(id: key)
            }
        }
```
（`item` = add 的返回值 / 编辑中的现对象；`titleText` 用表单标题字段变量名，照现文件。）PlanView 行 toggleDone 完成时不取消提醒（日程可重复勾，保持简单——spec 未要求）。
- [ ] **Step 3: `./scripts/build.sh && ./scripts/test.sh` → ✅✅；提交** `git commit -m "反馈⑥ T10 今天墨卡与行前提醒：三类行聚合、提醒区经期行移交、日程提醒行"`。

---

### Task 11: 种子 + UI 截图 + 终检（含 schema 部署提示）

**Files:**
- Modify: `Support/DebugSeeder.swift`
- Modify: `UITests/MapFilterReproTests.swift`
- Modify: `docs/RELEASE.md`（§一末尾加一行增量部署提醒）

**Interfaces:**
- Consumes: T2 TodoRepository。

- [ ] **Step 1: 种子**（她页种子段之后追加）：

```swift
        // 记得做种子：我做一条今天到期 + Ta做一条私密（今天卡/第四段/🔒 演示）
        let todoRepo = TodoRepository(context: context)
        let myID2 = coupleRepo.currentPartnerID(of: couple)
        let herID = CoupleRepository(context: context).otherPartner(of: couple)?.id
        _ = try? todoRepo.create(couple: couple, title: "帮她带充电宝", detail: nil,
                                 dueAt: Date(), assigneeID: myID2, authorID: herID,
                                 visibility: .sharedImmediately, place: nil, remindAt: nil,
                                 calendar: cal)
        _ = try? todoRepo.create(couple: couple, title: "查演出票", detail: "周五开票",
                                 dueAt: day(3), assigneeID: herID, authorID: myID2,
                                 visibility: .privateUntilRevealed, place: nil, remindAt: nil,
                                 calendar: cal)
```
- [ ] **Step 2: UI 用例**（attach 辅助之前加）：

```swift
    /// 反馈⑥：今天卡 / 记得做段 / 她月历紫窗
    @MainActor
    func testRound6Look() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()

        XCTAssertTrue(app.staticTexts["帮她带充电宝"].waitForExistence(timeout: 10), "今天卡未出现")
        attach(app, name: "R1-今天卡")

        app.buttons["小本本"].tap()
        app.buttons["记得做"].tap()
        XCTAssertTrue(app.staticTexts["📌 我做"].waitForExistence(timeout: 3), "记得做段未出现")
        attach(app, name: "R2-记得做段")

        app.buttons["她"].tap()
        sleep(2)
        attach(app, name: "R3-她月历紫窗")
    }
```
- [ ] **Step 3: RELEASE.md §一末尾加**：`> 反馈⑥ 起新增 CDTodoItem 实体与 CDPlanItem.remindAt 字段：发布含此改动的构建前，重跑一次本节（-InitCloudKitSchema → Deploy to Production，增量、老数据不动）。`
- [ ] **Step 4: 全门禁 + UI 全套**——`./scripts/gen.sh && ./scripts/build.sh && ./scripts/test.sh` ✅✅；`xcodebuild -only-testing:AnniversaryUITests`（resultBundlePath 放 scratchpad，导出 Read 截图核对：今天卡三行、记得做分组勾选圈、紫窗+🌸）。既有 6 用例全绿。
- [ ] **Step 5: 提交** `git commit -m "反馈⑥ T11 种子与 UI 验证：记得做两条、今天卡/第四段/紫窗三截图、部署提醒"`。

---

## 自审记录

- spec 覆盖：§一(T3/T6)、§二(T1/T2/T8/T9)、§三(T4+T8 复用)、§四(T10)、§五(T5/T8/T9/T10)、§六(T7)、§七(T1 schema + T11 RELEASE 提示，实际部署人工步骤)、§八(各任务 TDD + T11)。出圈零实现 ✓。
- 类型一致：TodoRepository/TodoRules/ReminderPlanner/OvulationWindow 签名在 T8/T9/T10 的用法逐一比对 ✓；LedgerListView(initialSegment:) 在 T10 使用 ✓；PanelAction `.todo` 与 MainShell 改动配套 ✓。
- 无占位：T7 的 frame 高度注明「以现行网格高度为准」是测量指令非 TBD；T8 地点行/公开确认「照 LedgerFormView 原样搬」为明确迁移指令（源文件在库）✓。
