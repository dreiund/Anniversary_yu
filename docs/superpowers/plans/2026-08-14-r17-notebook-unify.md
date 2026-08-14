# R17 小本本契合度三改 + 完成开关渲染修 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 待办点按统一为先看详情并支持照片;四段详情页地点一键导航;计划见面支持私密(开始见面自动公开);根修待办完成开关不刷新 bug。

**Architecture:** 数据层先行(CDEvidence 加 todoItem 父关系、CDMeeting 加作者/可见性/公开时间三字段、仓库 API),UI 层逐任务落:行级 @ObservedObject 根修 → 导航组件共享化 → 待办详情新页 → 表单照片 → 私密计划全过滤面。可见性判定复用 `LedgerRules.isVisible`,不造新函数。

**Tech Stack:** SwiftUI + Core Data(程序化模型 ModelSchema)+ CloudKit 双 store;XcodeGen;XCTest/XCUITest。

**Spec:** `docs/superpowers/specs/2026-08-14-r17-notebook-unify-private-plan-design.md`(计划从 spec 论证,执行者两份都读)

## Global Constraints

- 新建 .swift 文件后必须先 `./scripts/gen.sh` 再构建(xcodeproj 是生成物,不入库)。
- 门禁:`./scripts/build.sh` 打印 ✅构建通过、`./scripts/test.sh` 打印 ✅测试通过(含 UI 测试)。SourceKit 诊断是索引噪音,以脚本输出为准。
- raw 值入库跨设备:只许追加 case/字段,禁改禁删(DomainEnums 头注)。
- 文案全中文;日期用 Fmt.*(zh_CN)。
- 每个 commit 尾部带:`Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` 与 `Claude-Session: https://claude.ai/code/session_01QKnmr2idBpc7e7LJyhm1QR`。
- iOS 17.0 floor;深色模式用 DS 动态 token,禁硬编码颜色(小样十六进制色对应 DS token:actionBlue/parchment/canvas/hairline/inkMuted…)。
- UI 断言锚点用显式 `.accessibilityLabel`(R14 教训:多 Text 拼接分隔符随 locale 变)。

---

### Task 1: 数据层——模型增量 + 仓库 API

**Files:**
- Modify: `Domain/ModelSchema.swift`
- Modify: `Domain/ManagedObjects.swift`
- Modify: `Persistence/TodoRepository.swift`
- Modify: `Persistence/MeetingRepository.swift`
- Test: `Tests/TodoTests.swift`(追加)、`Tests/MeetingPrivacyTests.swift`(新建)、`Tests/ModelSchemaTests.swift`(追加)

**Interfaces:**
- Consumes: 现有 `EntryVisibility`(sharedImmediately=0/privateUntilRevealed=1)、`Thumbnailer.thumbnailData(from:)`、`LedgerRepository.appendEvidences` 同款模式。
- Produces(后续任务依赖的确切签名):
  - `CDTodoItem.evidences: NSSet?` / `CDEvidence.todoItem: CDTodoItem?`
  - `CDMeeting.authorPartnerID: UUID?` / `CDMeeting.visibilityRaw: Int16`(非空默认 0)/ `CDMeeting.revealedAt: Date?`
  - `TodoRepository.evidencesSorted(_ todo: CDTodoItem) -> [CDEvidence]`
  - `TodoRepository.addEvidences(_ todo: CDTodoItem, datas: [Data]) throws`
  - `TodoRepository.deleteEvidence(_ evidence: CDEvidence) throws`
  - `MeetingRepository.createPlanned(couple:title:city:plannedStart:plannedEnd:authorID:visibility:)`(新参默认 `authorID: UUID? = nil, visibility: EntryVisibility = .sharedImmediately`——既有调用点零改动)
  - `MeetingRepository.reveal(_ meeting: CDMeeting, at date: Date) throws`(幂等)
  - `MeetingRepository.start(_:at:)`:私密未公开时先置 revealedAt 再置 ongoing,单次 save

- [ ] **Step 1: 写失败测试(新建 Tests/MeetingPrivacyTests.swift + TodoTests 追加)**

`Tests/MeetingPrivacyTests.swift`(样板照 MeetingRepositoryTests 的 in-memory container 写法,复制其 setUp):

```swift
import XCTest
import CoreData
@testable import Anniversary

final class MeetingPrivacyTests: XCTestCase {
    var container: NSPersistentContainer!
    var context: NSManagedObjectContext { container.viewContext }

    override func setUp() {
        super.setUp()
        container = NSPersistentContainer(name: "Test", managedObjectModel: ModelSchema.model)
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores { _, _ in }
    }

    private func makeCouple() throws -> CDCouple {
        try CoupleRepository(context: context)
            .bootstrapIfNeeded(myName: "我", partnerName: "TA", anniversary: nil)
    }

    func testCreatePlannedDefaultsArePublicAndAuthorless() throws {
        let couple = try makeCouple()
        let m = try MeetingRepository(context: context).createPlanned(
            couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        XCTAssertNil(m.authorPartnerID)
        XCTAssertEqual(m.visibilityRaw, EntryVisibility.sharedImmediately.rawValue)
        XCTAssertNil(m.revealedAt)
    }

    func testCreatePlannedPrivateCarriesAuthorAndVisibility() throws {
        let couple = try makeCouple()
        let myID = CoupleRepository(context: context).currentPartnerID(of: couple)
        let m = try MeetingRepository(context: context).createPlanned(
            couple: couple, title: "惊喜", city: nil, plannedStart: nil, plannedEnd: nil,
            authorID: myID, visibility: .privateUntilRevealed)
        XCTAssertEqual(m.authorPartnerID, myID)
        XCTAssertEqual(m.visibilityRaw, EntryVisibility.privateUntilRevealed.rawValue)
    }

    func testRevealIsIdempotent() throws {
        let couple = try makeCouple()
        let repo = MeetingRepository(context: context)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil,
                                       plannedStart: nil, plannedEnd: nil,
                                       authorID: nil, visibility: .privateUntilRevealed)
        let t1 = Date(timeIntervalSince1970: 100)
        try repo.reveal(m, at: t1)
        XCTAssertEqual(m.revealedAt, t1)
        try repo.reveal(m, at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(m.revealedAt, t1)   // 时戳留痕,不可覆盖
    }

    func testStartAutoRevealsPrivateMeeting() throws {
        let couple = try makeCouple()
        let repo = MeetingRepository(context: context)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil,
                                       plannedStart: nil, plannedEnd: nil,
                                       authorID: nil, visibility: .privateUntilRevealed)
        let start = Date(timeIntervalSince1970: 500)
        try repo.start(m, at: start)
        XCTAssertEqual(m.revealedAt, start)   // 开始见面=自动公开(spec §四)
        XCTAssertEqual(m.statusRaw, MeetingStatus.ongoing.rawValue)
    }

    func testStartDoesNotStampRevealOnPublicMeeting() throws {
        let couple = try makeCouple()
        let repo = MeetingRepository(context: context)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil,
                                       plannedStart: nil, plannedEnd: nil)
        try repo.start(m, at: Date())
        XCTAssertNil(m.revealedAt)   // 公开见面不需要公开时戳
    }

    /// 可见性判定表:meeting 口径直接复用 LedgerRules.isVisible(spec §四)
    func testVisibilityTable() {
        let me = UUID(), other = UUID()
        let priv = EntryVisibility.privateUntilRevealed.rawValue
        let pub = EntryVisibility.sharedImmediately.rawValue
        // 作者自己恒可见
        XCTAssertTrue(LedgerRules.isVisible(authorID: me, myID: me, visibilityRaw: priv, revealedAt: nil))
        // 对方的私密未公开不可见
        XCTAssertFalse(LedgerRules.isVisible(authorID: other, myID: me, visibilityRaw: priv, revealedAt: nil))
        // 公开后可见
        XCTAssertTrue(LedgerRules.isVisible(authorID: other, myID: me, visibilityRaw: priv, revealedAt: Date()))
        // 旧数据 nil 作者 + raw 0 = 双方可见
        XCTAssertTrue(LedgerRules.isVisible(authorID: nil, myID: me, visibilityRaw: pub, revealedAt: nil))
    }
}
```

`Tests/TodoTests.swift` 追加(照该文件既有 container 写法):

```swift
    func testEvidenceAddSortDelete() throws {
        let couple = try makeCouple()   // 若 TodoTests 无此 helper,照本文件既有建 couple 方式
        let repo = TodoRepository(context: context)
        let todo = try repo.create(couple: couple, title: "带充电宝", detail: nil, dueAt: Date(),
                                   assigneeID: nil, authorID: nil, visibility: .sharedImmediately,
                                   place: nil, remindAt: nil, calendar: .current)
        XCTAssertEqual(repo.evidencesSorted(todo).count, 0)
        try repo.addEvidences(todo, datas: [Data([0x1]), Data([0x2])])
        try repo.addEvidences(todo, datas: [Data([0x3])])
        let sorted = repo.evidencesSorted(todo)
        XCTAssertEqual(sorted.map(\.sortIndex), [0, 1, 2])   // 二次追加续排不重叠
        try repo.deleteEvidence(sorted[1])
        XCTAssertEqual(repo.evidencesSorted(todo).count, 2)
    }

    func testDeleteTodoCascadesEvidences() throws {
        let couple = try makeCouple()
        let repo = TodoRepository(context: context)
        let todo = try repo.create(couple: couple, title: "x", detail: nil, dueAt: Date(),
                                   assigneeID: nil, authorID: nil, visibility: .sharedImmediately,
                                   place: nil, remindAt: nil, calendar: .current)
        try repo.addEvidences(todo, datas: [Data([0x1])])
        try repo.delete(todo)
        let fetch = NSFetchRequest<CDEvidence>(entityName: "CDEvidence")
        XCTAssertEqual((try context.fetch(fetch)).count, 0)   // 删父级联删照片
    }
```

`Tests/ModelSchemaTests.swift` 追加:

```swift
    func testR17SchemaAdditions() {
        let model = ModelSchema.model
        let meeting = model.entitiesByName["CDMeeting"]!
        XCTAssertNotNil(meeting.attributesByName["authorPartnerID"])
        XCTAssertNotNil(meeting.attributesByName["visibilityRaw"])
        XCTAssertFalse(meeting.attributesByName["visibilityRaw"]!.isOptional)
        XCTAssertNotNil(meeting.attributesByName["revealedAt"])
        let todo = model.entitiesByName["CDTodoItem"]!
        let evidences = todo.relationshipsByName["evidences"]!
        XCTAssertEqual(evidences.destinationEntity?.name, "CDEvidence")
        XCTAssertEqual(evidences.deleteRule, .cascadeDeleteRule)
        let inverse = model.entitiesByName["CDEvidence"]!.relationshipsByName["todoItem"]!
        XCTAssertEqual(inverse.inverseRelationship?.name, "evidences")
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh 2>&1 | tail -20`
Expected: 编译失败(createPlanned 无 authorID 参、CDMeeting 无 authorPartnerID 等)——编译失败即"失败测试"成立。

- [ ] **Step 3: 实现模型增量**

`Domain/ModelSchema.swift`:meeting 实体三属性(照 ledger 的同名字段样式):

```swift
        let meeting = entity("CDMeeting", CDMeeting.self, [
            attr("id", .UUIDAttributeType),
            attr("index", .integer32AttributeType, optional: false, defaultValue: 0),
            attr("title", .stringAttributeType),
            attr("city", .stringAttributeType),
            attr("plannedStart", .dateAttributeType),
            attr("plannedEnd", .dateAttributeType),
            attr("startedAt", .dateAttributeType),
            attr("endedAt", .dateAttributeType),
            attr("statusRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("coverPhotoID", .UUIDAttributeType),
            attr("authorPartnerID", .UUIDAttributeType),                                   // R17 私密计划
            attr("visibilityRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("revealedAt", .dateAttributeType),
        ])
```

关系区追加一行(挨着 `oneToMany(ledger, "evidences", evidence, "ledgerEntry")`):

```swift
        oneToMany(todo, "evidences", evidence, "todoItem")
```

`Domain/ManagedObjects.swift`:CDMeeting 追加三个 @NSManaged;CDTodoItem 追加 `@NSManaged var evidences: NSSet?`;CDEvidence 追加 `@NSManaged var todoItem: CDTodoItem?`。

- [ ] **Step 4: 实现仓库 API**

`Persistence/TodoRepository.swift` 追加(照 LedgerRepository 同款,不抽公共层——spec §二):

```swift
    func evidencesSorted(_ todo: CDTodoItem) -> [CDEvidence] {
        ((todo.evidences as? Set<CDEvidence>) ?? [])
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func addEvidences(_ todo: CDTodoItem, datas: [Data]) throws {
        let start = (evidencesSorted(todo).last?.sortIndex).map { $0 + 1 } ?? 0
        for (i, data) in datas.enumerated() {
            let evidence = CDEvidence(context: context)
            evidence.id = UUID()
            evidence.imageData = data
            evidence.thumbnailData = Thumbnailer.thumbnailData(from: data)
            evidence.sortIndex = start + Int32(i)
            evidence.todoItem = todo
        }
        try context.save()
    }

    func deleteEvidence(_ evidence: CDEvidence) throws {
        context.delete(evidence)
        try context.save()
    }
```

`Persistence/MeetingRepository.swift`:

```swift
    @discardableResult
    func createPlanned(couple: CDCouple, title: String?, city: String?,
                       plannedStart: Date?, plannedEnd: Date?,
                       authorID: UUID? = nil,
                       visibility: EntryVisibility = .sharedImmediately) throws -> CDMeeting {
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
        meeting.authorPartnerID = authorID          // R17 私密计划:作者+可见性(默认口径=旧行为)
        meeting.visibilityRaw = visibility.rawValue
        meeting.couple = couple
        try context.save()
        return meeting
    }

    /// 公开给 TA:一次性置戳(同小本本 reveal 语义),不碰 visibilityRaw
    func reveal(_ meeting: CDMeeting, at date: Date) throws {
        guard meeting.revealedAt == nil else { return }
        meeting.revealedAt = date
        try context.save()
    }

    func start(_ meeting: CDMeeting, at date: Date) throws {
        // 开始见面=自动公开(R17 spec §四单点收口):私密未公开先置戳,同一保存
        if meeting.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue,
           meeting.revealedAt == nil {
            meeting.revealedAt = date
        }
        meeting.statusRaw = MeetingStatus.ongoing.rawValue
        meeting.startedAt = date
        try context.save()
    }
```

- [ ] **Step 5: 门禁绿 + 提交**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: ✅构建通过 / ✅测试通过(既有 MeetingRepositoryTests/TodoTests/ModelSchemaTests 全绿——默认参保证零破坏)。

```bash
git add Domain/ModelSchema.swift Domain/ManagedObjects.swift Persistence/TodoRepository.swift Persistence/MeetingRepository.swift Tests/TodoTests.swift Tests/MeetingPrivacyTests.swift Tests/ModelSchemaTests.swift
git commit -m "R17-T1 数据层:待办照片关系+见面私密三字段+仓库API(开始见面自动公开)"
```
(新建了 Tests/MeetingPrivacyTests.swift → 提交前先 `./scripts/gen.sh`。)

---

### Task 2: 待办完成开关渲染根修(TodoRow 行级订阅)

**Files:**
- Modify: `Features/Ledger/LedgerListView.swift`
- Test: `UITests/MapFilterReproTests.swift`(追加)

**Interfaces:**
- Consumes: 种子数据(`--seed-map-demo`):待办「查演出票」(作者=本机,未完成,canToggle=true)、「帮她带充电宝」(作者=对方)。
- Produces: 私有 `struct TodoRow: View { @ObservedObject var todo: CDTodoItem; let myID: UUID?; var onTap: () -> Void }`,勾选圈带显式 label「完成 <标题>」/「取消完成 <标题>」;Task 4 在同文件把 onTap 从"编辑/弹窗"改接详情推入。

- [ ] **Step 1: 写回归 UI 测试(先写,预期失败——bug 时有时无,跑出结果照记,不因偶绿跳过修复)**

`UITests/MapFilterReproTests.swift` 追加:

```swift
    /// R17 §五:完成开关点按后行必须立刻重绘(R12 MemoRow 同族回归)。
    /// 断言锚点=勾选圈显式 label 翻转(完成 x ↔ 取消完成 x),双击验证第二次点按仍重绘。
    @MainActor
    func testTodoToggleRedrawsRow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()

        app.buttons["小本本"].tap()
        let todosTab = app.buttons["待办"]
        XCTAssertTrue(todosTab.waitForExistence(timeout: 8), "小本本四段未出现")
        todosTab.tap()

        let toggle = app.buttons["完成 查演出票"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "勾选圈未带显式 label")
        toggle.tap()
        XCTAssertTrue(app.buttons["取消完成 查演出票"].waitForExistence(timeout: 3),
                      "第一次点按后行未重绘")
        app.buttons["取消完成 查演出票"].tap()
        XCTAssertTrue(app.buttons["完成 查演出票"].waitForExistence(timeout: 3),
                      "第二次点按后行未重绘(R12 同族值缓存)")
    }
```

注:底栏 tab 名以 MainShell 实际为准(足迹/我们同款写法);若小本本入口是 tab「小本本」则如上,若经其他入口,进页方式照文件里 testRound9Look 既有导航步骤抄。

- [ ] **Step 2: 跑该测试记录结果**

Run: `xcodebuild test -project Anniversary.xcodeproj -scheme Anniversary -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AnniversaryUITests/MapFilterReproTests/testTodoToggleRedrawsRow 2>&1 | tail -5`
Expected: 失败于"勾选圈未带显式 label"(label 还没加)。记录输出。

- [ ] **Step 3: 抽 TodoRow 行级结构体**

`Features/Ledger/LedgerListView.swift`:删掉 `private func todoRow(_ todo:)` 与 `private func todoMeta(_:)`,在文件底部(TodoDetailSheet 前)新增:

```swift
/// R17 §五根修:行级 @ObservedObject 订阅对象变更——父视图重算与否都能重绘
/// (R12 MemoRow 同款;此前 todoRow 是内联 builder,isDone 翻转不改 todoItems.count,行不刷新)
private struct TodoRow: View {
    @ObservedObject var todo: CDTodoItem
    let myID: UUID?
    var onTap: () -> Void
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                if TodoRules.canToggleDone(authorID: todo.authorPartnerID,
                                           assigneeID: todo.assigneePartnerID, myID: myID) {
                    try? TodoRepository(context: context).setDone(todo, done: !todo.isDone, at: Date())
                    if todo.isDone, let id = todo.id {
                        ReminderScheduler.cancel(id: ReminderPlanner.todoID(id))   // 完成即取消提醒
                    }
                }
            } label: {
                ZStack {
                    Circle().fill(DS.parchment).frame(width: 34, height: 34)
                    Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(todo.isDone ? DS.actionBlue : DS.chipBorder)
                }
            }
            .buttonStyle(DSPressEffect())
            .accessibilityLabel("\(todo.isDone ? "取消完成" : "完成") \(todo.title ?? "")")
            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(todo.isDone ? DS.inkMuted : DS.ink)
                    .strikethrough(todo.isDone, color: DS.inkMuted)
                    .lineLimit(1)
                Text(meta).dsFootnote()
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.darkCard).stroke(DS.hairline, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var meta: String {
        var parts: [String] = []
        if let due = todo.dueAt { parts.append(Fmt.monthDay.string(from: due)) }
        if !LedgerRules.isRevealed(visibilityRaw: todo.visibilityRaw, revealedAt: todo.revealedAt) {
            parts.append("🔒")
        }
        if todo.isDone { parts.append("已完成") }
        parts.append(todo.assigneePartnerID == myID ? "我做" : "Ta做")
        return parts.joined(separator: " · ")
    }
}
```

调用点(todosSection 的 ForEach 里,原 `todoRow($0)` 位置)改为——外层左滑包装逻辑保持原样(canEdit 才包 SwipeDeleteRow),行体换成:

```swift
    @ViewBuilder
    private func todoRowEntry(_ todo: CDTodoItem) -> some View {
        let canEdit = TodoRules.canEdit(authorID: todo.authorPartnerID, myID: myID)
        let row = TodoRow(todo: todo, myID: myID) {
            if canEdit { editingTodo = todo } else { viewingTodo = todo }   // Task 4 改接详情
        }
        if canEdit {
            SwipeDeleteRow(id: todo.objectID, openID: $openSwipeID) {
                pendingDeleteTodo = todo
            } content: { row }
        } else {
            row
        }
    }
```

ForEach 调 `todoRowEntry($0)`。管理模式(selecting)分支若原来对待办有专门处理则保持不变。

- [ ] **Step 4: 跑回归测试至绿 + 全量门禁**

Run: 同 Step 2 命令,Expected: PASS(双击断言过)。再 `./scripts/build.sh && ./scripts/test.sh`,Expected: 全绿。

- [ ] **Step 5: 提交**

```bash
git add Features/Ledger/LedgerListView.swift UITests/MapFilterReproTests.swift
git commit -m "R17-T2 待办完成开关根修:TodoRow 行级 @ObservedObject+显式 label+双击回归(R12 同族)"
```

---

### Task 3: 导航组件共享化 + 好事详情地点行

**Files:**
- Modify: `DesignSystem/DSButtons.swift`
- Modify: `Features/Plan/PlanItemDetailSheet.swift`
- Modify: `Features/Ledger/LedgerDetailView.swift`

**Interfaces:**
- Consumes: `AmapNavigator.navigate(name:latitude:longitude:)`、`openInMapsNavigation(place:)`(PlanItemDetailSheet.swift 底部全局函数,保留原位)、`PlaceMiniMapSheet(place:)`。
- Produces: `struct SmallBluePillButtonStyle: ButtonStyle`(internal,DSButtons.swift);`EvidenceViewer` 由 private 提为 internal(留在 LedgerDetailView.swift);LedgerDetailView 的地点行范式(Task 4 抄同款)。

- [ ] **Step 1: 提升 SmallBluePillButtonStyle**

把 `Features/Plan/PlanItemDetailSheet.swift` 底部的 `private struct SmallBluePillButtonStyle` 整体剪切到 `DesignSystem/DSButtons.swift` 末尾,去掉 `private`,注释改为:

```swift
/// 小尺寸行动蓝药丸(R17 §三共享化):详情页地点行内联「导航」钮专用紧凑尺寸
/// (BluePillButtonStyle 是大号 CTA;行前日程查看页/小本本四段详情共用本样式)
struct SmallBluePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(Capsule().fill(DS.actionBlue))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
```

- [ ] **Step 2: LedgerDetailView 地点行改造 + EvidenceViewer 提升**

`Features/Ledger/LedgerDetailView.swift`:
1. `private struct EvidenceViewer` → `struct EvidenceViewer`(注释补一句「R17:待办详情共用」)。
2. `infoRows` 里删掉地点行(`if let placeName = entry.place?.name` 那段)。
3. 信息行 GroupedSection 之后、证据区之前插入独立地点行(PlanItemDetailSheet 同款范式):

```swift
                if let place = entry.place {
                    GroupedSection {
                        HStack {
                            Button {
                                if place.latitude != 0 || place.longitude != 0 { showMiniMap = true }
                            } label: {
                                Text("📍 \(place.name ?? "")").dsBody()
                                    .foregroundStyle(place.latitude != 0 || place.longitude != 0
                                                     ? DS.actionBlue : DS.inkMuted)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            if place.latitude != 0 || place.longitude != 0 {
                                Button("导航") { openInMapsNavigation(place: place) }
                                    .buttonStyle(SmallBluePillButtonStyle())
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                }
```

4. 状态与 sheet:`@State private var showMiniMap = false` + content 的 modifier 链追加:

```swift
        .sheet(isPresented: $showMiniMap) {
            if let place = entry.place { PlaceMiniMapSheet(place: place) }
        }
```

- [ ] **Step 3: 门禁绿**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 全绿(纯 UI 改动;PlanItemDetailSheet 引用共享样式后行为不变)。

- [ ] **Step 4: 提交**

```bash
git add DesignSystem/DSButtons.swift Features/Plan/PlanItemDetailSheet.swift Features/Ledger/LedgerDetailView.swift
git commit -m "R17-T3 导航共享化:SmallBluePillButtonStyle 提升+好事详情地点行导航+EvidenceViewer internal"
```

---

### Task 4: 待办详情页(推入式,1A)

**Files:**
- Create: `Features/Ledger/TodoDetailView.swift`
- Modify: `Features/Ledger/LedgerListView.swift`
- Modify: `Features/Ledger/LedgerDetailView.swift`(仅 `EvidenceIndex` 去 private,T3 已提升 EvidenceViewer)
- Modify: `Support/Formatters.swift`(新增 monthDayHM)
- Test: `UITests/MapFilterReproTests.swift`(追加)

**Interfaces:**
- Consumes: T1 `TodoRepository.evidencesSorted`;T2 `TodoRow`(onTap 改接推入);T3 `SmallBluePillButtonStyle`/`EvidenceViewer`/地点行范式;`TodoRules.canEdit/canToggleDone`;`LedgerRules.isRevealed`;`ReminderPlanner.todoID`/`ReminderScheduler.cancel`。
- Produces: `struct TodoDetailView: View`(init `TodoDetailView(todo: CDTodoItem)`);LedgerListView 待办点行统一推入详情,`TodoDetailSheet` 删除。

- [ ] **Step 1: 写 UI 测试(追加)**

```swift
    /// R17 §二:待办点行(作者/非作者同路)推入详情;作者见「⋯」菜单;完成大钮翻转;带坐标地点出导航钮
    @MainActor
    func testTodoDetailUnified() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()

        app.buttons["小本本"].tap()
        let todosTab = app.buttons["待办"]
        XCTAssertTrue(todosTab.waitForExistence(timeout: 8))
        todosTab.tap()

        // 非作者条目(帮她带充电宝,作者=对方,assignee=我):推入详情,无编辑菜单,有完成钮+导航钮
        app.staticTexts["帮她带充电宝"].tap()
        XCTAssertTrue(app.staticTexts["📍 演示花店"].waitForExistence(timeout: 5), "详情未推入或地点行缺失")
        XCTAssertTrue(app.buttons["导航"].exists, "带坐标地点未出导航钮")
        XCTAssertFalse(app.buttons["待办详情菜单"].exists, "非作者不该有编辑菜单")
        let doneBig = app.buttons["完成"]
        XCTAssertTrue(doneBig.exists, "assignee 该有完成大钮")
        doneBig.tap()
        XCTAssertTrue(app.buttons["取消完成"].waitForExistence(timeout: 3), "详情完成钮未翻转")
        app.buttons["取消完成"].tap()
        app.navigationBars.buttons.firstMatch.tap()   // 返回列表

        // 作者条目(查演出票):详情有「⋯」菜单,菜单里能进编辑表单
        app.staticTexts["查演出票"].tap()
        let menu = app.buttons["待办详情菜单"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "作者详情缺编辑菜单")
        menu.tap()
        app.buttons["编辑"].tap()
        XCTAssertTrue(app.navigationBars["编辑待办"].waitForExistence(timeout: 5), "菜单未进编辑表单")
        app.buttons["取消"].tap()
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `-only-testing:AnniversaryUITests/MapFilterReproTests/testTodoDetailUnified`(命令同 T2 Step 2)
Expected: FAIL——点「帮她带充电宝」现在弹的是旧只读 sheet,无「📍 演示花店」行。

- [ ] **Step 3: 新建 TodoDetailView.swift**

```swift
import SwiftUI
import CoreData

/// 待办详情(R17 §二,1A 推入式):版式照 LedgerDetailView——主体卡+信息行+地点行+照片区,
/// 作者右上「⋯」编辑/删除,canToggle 者底部完成大钮;公开仍走表单开关,本页不设公开钮(spec §八)
struct TodoDetailView: View {
    @ObservedObject var todo: CDTodoItem
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDCouple.createdAt)]) private var couples: FetchedResults<CDCouple>

    @State private var confirmDelete = false
    @State private var showEdit = false
    @State private var showMiniMap = false
    @State private var viewerIndex: Int?

    private var myID: UUID? {
        couples.first.flatMap { CoupleRepository(context: context).currentPartnerID(of: $0) }
    }
    private var isMine: Bool { TodoRules.canEdit(authorID: todo.authorPartnerID, myID: myID) }
    private var canToggle: Bool {
        TodoRules.canToggleDone(authorID: todo.authorPartnerID,
                                assigneeID: todo.assigneePartnerID, myID: myID)
    }
    private var revealed: Bool {
        LedgerRules.isRevealed(visibilityRaw: todo.visibilityRaw, revealedAt: todo.revealedAt)
    }

    var body: some View {
        if todo.managedObjectContext == nil || todo.isDeleted {
            Color.clear.onAppear { dismiss() }   // 对方远程删除守卫(P6 F-2 同款)
        } else {
            content
        }
    }

    private var content: some View {
        let evidences = TodoRepository(context: context).evidencesSorted(todo)
        return ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ParchmentCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("待办 · \(todo.assigneePartnerID == myID ? "我做" : "Ta做")")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.actionBlue)
                                .padding(.vertical, 4).padding(.horizontal, 10)
                                .background(Capsule().fill(DS.actionBlue.opacity(0.14)))
                            Spacer()
                            if !revealed {
                                Text("🔒 仅自己可见").dsFootnote()
                            }
                        }
                        Text(todo.title ?? "").dsPageTitle()
                        if let detail = todo.detail, !detail.isEmpty {
                            Text(detail).dsBody().lineSpacing(5)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupedSection {
                    ForEach(Array(infoRows.enumerated()), id: \.offset) { i, row in
                        GroupedRow(title: row.title, value: row.value,
                                   valueColor: row.color,
                                   showsDivider: i < infoRows.count - 1)
                    }
                }

                if let place = todo.place {
                    GroupedSection {
                        HStack {
                            Button {
                                if place.latitude != 0 || place.longitude != 0 { showMiniMap = true }
                            } label: {
                                Text("📍 \(place.name ?? "")").dsBody()
                                    .foregroundStyle(place.latitude != 0 || place.longitude != 0
                                                     ? DS.actionBlue : DS.inkMuted)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            if place.latitude != 0 || place.longitude != 0 {
                                Button("导航") { openInMapsNavigation(place: place) }
                                    .buttonStyle(SmallBluePillButtonStyle())
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                }

                if !evidences.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("照片").dsSectionTitle()
                            Text("\(evidences.count) 张 · 点开大图").dsFootnote()
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(evidences.enumerated()), id: \.element.objectID) { i, evidence in
                                    if let data = evidence.thumbnailData, let ui = UIImage(data: data) {
                                        Image(uiImage: ui).resizable().scaledToFill()
                                            .frame(width: 110, height: 110)
                                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                                            .dsPhotoShadow()
                                            .onTapGesture { viewerIndex = i }
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .navigationTitle("待办")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isMine {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("编辑") { showEdit = true }
                        Button("删除", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("待办详情菜单")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if canToggle {
                Button(todo.isDone ? "取消完成" : "完成") {
                    try? TodoRepository(context: context).setDone(todo, done: !todo.isDone, at: Date())
                    if todo.isDone, let id = todo.id {
                        ReminderScheduler.cancel(id: ReminderPlanner.todoID(id))   // 完成即取消提醒
                    }
                }
                .buttonStyle(BluePillButtonStyle(fullWidth: true))
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .alert("删除这条待办？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                let id = todo.id
                try? TodoRepository(context: context).delete(todo)
                if let id { ReminderScheduler.cancel(id: ReminderPlanner.todoID(id)) }
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showEdit) { TodoFormView(mode: .edit(todo)) }
        .sheet(isPresented: $showMiniMap) {
            if let place = todo.place { PlaceMiniMapSheet(place: place) }
        }
        .fullScreenCover(item: Binding(
            get: { viewerIndex.map { EvidenceIndex(id: $0) } },
            set: { viewerIndex = $0?.id })) { index in
            EvidenceViewer(evidences: evidences, index: index.id)
        }
    }

    private var infoRows: [(title: String, value: String, color: Color)] {
        var rows: [(String, String, Color)] = [("记录人", authorName.isEmpty ? "—" : authorName, DS.inkMuted)]
        rows.append(("目标日", todo.dueAt.map { Fmt.monthDay.string(from: $0) } ?? "—", DS.inkMuted))
        if let remindAt = todo.remindAt {
            rows.append(("提醒", Fmt.monthDayHM.string(from: remindAt), DS.inkMuted))
        }
        if todo.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue {
            if let revealedAt = todo.revealedAt {
                rows.append(("可见性", "\(Fmt.monthDay.string(from: revealedAt)) 已公开", DS.dsGreen))
            } else {
                rows.append(("可见性", "仅自己可见 🔒", DS.inkMuted))
            }
        } else {
            rows.append(("可见性", "双方可见", DS.dsGreen))
        }
        rows.append(("完成态", todo.isDone ? "已完成" : "未完成", todo.isDone ? DS.dsGreen : DS.inkMuted))
        return rows
    }

    private var authorName: String {
        guard let id = todo.authorPartnerID, let couple = couples.first else { return "" }
        let repo = CoupleRepository(context: context)
        if id == repo.currentPartnerID(of: couple) { return "我" }
        return repo.otherPartner(of: couple)?.name ?? "TA"
    }
}
```

注:`EvidenceIndex` 在 LedgerDetailView.swift 里是 private → 去掉 private(同 T3 的 EvidenceViewer)。`Fmt.monthDayHM` 现不存在,`Support/Formatters.swift` 的 monthDayWeek 行下补一行:

```swift
    static let monthDayHM = make("M月d日 HH:mm")   // R17:待办详情提醒行
```

- [ ] **Step 4: LedgerListView 接线**

1. 删 `@State private var editingTodo` / `@State private var viewingTodo` 与对应两个 `.sheet`;删文件底部整个 `TodoDetailSheet` struct。
2. 加 `@State private var pushedTodo: CDTodoItem?`,modifier 链(alert 群旁)加:

```swift
        .navigationDestination(item: $pushedTodo) { TodoDetailView(todo: $0) }
```

3. T2 的 `todoRowEntry` 闭包改为统一推入:

```swift
        let row = TodoRow(todo: todo, myID: myID) { pushedTodo = todo }
```

- [ ] **Step 5: gen + 测试至绿 + 提交**

Run: `./scripts/gen.sh && ./scripts/build.sh && ./scripts/test.sh`(新文件必须先 gen)
Expected: 全绿,含 testTodoDetailUnified 与 T2 回归。

```bash
git add Features/Ledger/TodoDetailView.swift Features/Ledger/LedgerListView.swift Features/Ledger/LedgerDetailView.swift Support/Formatters.swift UITests/MapFilterReproTests.swift
git commit -m "R17-T4 待办详情推入式统一:TodoDetailView 新页+TodoDetailSheet 删除+点行同路"
```

---

### Task 5: 待办表单照片栏 + 列表行缩略图

**Files:**
- Modify: `Features/Ledger/TodoFormView.swift`
- Modify: `Features/Ledger/LedgerListView.swift`(TodoRow)

**Interfaces:**
- Consumes: T1 `TodoRepository.evidencesSorted/addEvidences/deleteEvidence`;LedgerFormView 的照片选择器范式(pickerItems/photoDatas/evidencesToDelete/onChange 加载)。
- Produces: 待办表单「照片」栏(create/edit 都可增删,上限 9);TodoRow meta 行尾 26pt 首图缩略。

- [ ] **Step 1: TodoFormView 加照片栏**

1. `import PhotosUI`;状态区追加:

```swift
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photoDatas: [Data] = []
    @State private var evidencesToDelete: [CDEvidence] = []
```

2. 计算属性(照 LedgerFormView.existingEvidences):

```swift
    private var existingEvidences: [CDEvidence] {
        guard let todo = editingTodo else { return [] }
        return TodoRepository(context: context).evidencesSorted(todo)
            .filter { !evidencesToDelete.contains($0) }
    }
```

3. 「提醒我」GroupedSection 之前插入照片段(LedgerFormView 同款,label 用「照片」):

```swift
                    GroupedSection {
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: 9, matching: .images) {
                            HStack {
                                Text("照片").dsBody()
                                Spacer()
                                Text(photoDatas.isEmpty && existingEvidences.isEmpty
                                     ? "＋ 添加" : "已有 \(existingEvidences.count + photoDatas.count) 张")
                                    .dsCaption()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 11)
                        }
                        if !existingEvidences.isEmpty || !photoDatas.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(existingEvidences, id: \.objectID) { evidence in
                                        evidenceThumb(evidence)
                                    }
                                    ForEach(Array(photoDatas.enumerated()), id: \.offset) { _, data in
                                        if let ui = UIImage(data: data) {
                                            Image(uiImage: ui).resizable().scaledToFill()
                                                .frame(width: 52, height: 52)
                                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                                        }
                                    }
                                }
                                .padding(.horizontal, 14).padding(.bottom, 11)
                            }
                        }
                    }
```

4. `evidenceThumb(_:)` 私有函数与 `.onChange(of: pickerItems)` 加载块:逐字照 LedgerFormView 同名实现复制(52pt 缩略 + 右上 xmark 删除标记;onChange 里 loadTransferable 收集 photoDatas)。
5. `save()` 里 `savedTodo` 赋值后、提醒排程前追加:

```swift
        for evidence in evidencesToDelete { try? repo.deleteEvidence(evidence) }
        if !photoDatas.isEmpty, let savedTodo { try? repo.addEvidences(savedTodo, datas: photoDatas) }
```

- [ ] **Step 2: TodoRow 缩略图**

TodoRow(T2)meta 文字行改为 HStack 尾缀首图(newCard 同款 26pt):

```swift
                HStack(spacing: 8) {
                    Text(meta).dsFootnote()
                    Spacer()
                    if let thumb = TodoRepository(context: context).evidencesSorted(todo).first?.thumbnailData,
                       let ui = UIImage(data: thumb) {
                        Image(uiImage: ui).resizable().scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .allowsHitTesting(false)
                    }
                }
```

- [ ] **Step 3: 门禁绿 + 提交**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 全绿(表单照片走 T1 已测仓库 API;PhotosPicker 选图交互不做 UI 自动化——模拟器相册权限弹窗成本高,双机验收覆盖)。

```bash
git add Features/Ledger/TodoFormView.swift Features/Ledger/LedgerListView.swift
git commit -m "R17-T5 待办照片:表单照片栏(9张上限)+列表行首图缩略"
```

---

### Task 6: 私密计划见面(3A)——表单开关 + 全过滤面

**Files:**
- Create: `Features/Meetings/MeetingVisibility.swift`
- Modify: `Features/Meetings/MeetingFormView.swift`
- Modify: `Features/Meetings/MeetingsView.swift`
- Modify: `Features/Plan/PlanView.swift`
- Modify: `Features/Home/HomeView.swift`
- Modify: `Features/Places/PlacesMapView.swift`
- Modify: `Support/DebugSeeder.swift`
- Test: `UITests/MapFilterReproTests.swift`(追加)

**Interfaces:**
- Consumes: T1 `createPlanned(authorID:visibility:)`/`reveal`/start 自动公开;`LedgerRules.isVisible/isRevealed`;`EntryVisibility`。
- Produces:

```swift
// Features/Meetings/MeetingVisibility.swift
extension CDMeeting {
    /// 对 myID 是否可见(R17 私密计划过滤;复用小本本口径,不造新函数)
    func isVisible(to myID: UUID?) -> Bool
    /// 私密且未公开(卡片🔒chip / 表单锁定判定共用)
    var isPrivateUnrevealed: Bool
}
struct MeetingPrivacyChip: View   // 「🔒 私密」橙系胶囊(计划卡/行前页共用)
```

- [ ] **Step 1: 写 UI 测试(追加)+ 种子加两条计划**

`Support/DebugSeeder.swift`:记得做种子之后追加(城市避开「上海」,防干扰既有左滑测试的锚点):

```swift
        // R17 私密计划种子:我的私密(列表见🔒chip)+ 对方的私密(全面不可见的验证样本)
        _ = try? meetings.createPlanned(couple: couple, title: "演示惊喜", city: "南京",
                                        plannedStart: day(20), plannedEnd: day(22),
                                        authorID: myID, visibility: .privateUntilRevealed)
        _ = try? meetings.createPlanned(couple: couple, title: "演示他方私密", city: "杭州",
                                        plannedStart: day(30), plannedEnd: day(31),
                                        authorID: herID, visibility: .privateUntilRevealed)
```

`UITests/MapFilterReproTests.swift` 追加:

```swift
    /// R17 §四:私密计划——自己的带🔒chip 可见,对方的全面隐形(列表);表单开关锁定文案
    @MainActor
    func testPrivatePlannedMeetingVisibility() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()

        app.buttons["足迹"].tap()
        XCTAssertTrue(app.staticTexts["南京 · 演示惊喜"].waitForExistence(timeout: 8),
                      "我的私密计划该出现在列表")
        XCTAssertTrue(app.staticTexts["🔒 私密"].exists, "私密计划卡缺🔒chip")
        XCTAssertFalse(app.staticTexts["杭州 · 演示他方私密"].exists,
                       "对方的私密计划不该出现在列表")

        // 进行前计划页:头部同款 chip;编辑表单里私密开关存在且开着
        app.staticTexts["南京 · 演示惊喜"].tap()
        XCTAssertTrue(app.staticTexts["🔒 私密"].waitForExistence(timeout: 5), "行前页头部缺 chip")
        app.navigationBars.buttons["编辑"].tap()   // 行前页 toolbar 编辑(区别于日程行内编辑钮)
        let toggle = app.switches["私密"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "计划见面表单缺私密开关")
        XCTAssertEqual(toggle.value as? String, "1", "私密开关应为开")
        app.buttons["取消"].tap()
    }
```

注:PlanView 顶部编辑入口按钮名以实际为准(showEditForm 的触发钮;若是「⋯」菜单则照 PlanView 现状写导航步骤)。

- [ ] **Step 2: 跑测试确认失败**

Run: `-only-testing:AnniversaryUITests/MapFilterReproTests/testPrivatePlannedMeetingVisibility`
Expected: FAIL——「演示他方私密」出现在列表(还没过滤)。

- [ ] **Step 3: 新建 MeetingVisibility.swift**

```swift
import SwiftUI

/// R17 私密计划(spec §四):可见性判定与🔒标识——判定复用小本本口径,不造新函数
extension CDMeeting {
    /// 对 myID 是否可见:我的恒可见;对方的私密未公开不可见;旧数据(nil 作者/raw 0)恒可见
    func isVisible(to myID: UUID?) -> Bool {
        LedgerRules.isVisible(authorID: authorPartnerID, myID: myID,
                              visibilityRaw: visibilityRaw, revealedAt: revealedAt)
    }

    /// 私密且未公开(计划卡🔒chip / 表单锁定判定共用)
    var isPrivateUnrevealed: Bool {
        visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue && revealedAt == nil
    }
}

/// 「🔒 私密」小胶囊(计划卡/行前计划页头部共用;橙系沿用类别徽章的透明底范式,深浅色自适应)
struct MeetingPrivacyChip: View {
    var body: some View {
        Text("🔒 私密")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DS.dsOrange)
            .padding(.vertical, 2).padding(.horizontal, 8)
            .background(Capsule().fill(DS.dsOrange.opacity(0.14)))
    }
}
```

- [ ] **Step 4: MeetingFormView 私密开关**

1. 状态与判定(照 TodoFormView 同款):

```swift
    @State private var visibility: EntryVisibility = .sharedImmediately
    @State private var confirmReveal = false
```

```swift
    private var myID: UUID? {
        let repo = CoupleRepository(context: context)
        switch mode {
        case .create(let couple): return repo.currentPartnerID(of: couple)
        case .edit(let m): return m.couple.flatMap { repo.currentPartnerID(of: $0) }
        }
    }
    /// 开关只在「新建」或「计划中 && 我是作者」出现(spec §四);已公开=锁定
    private var showsPrivacyToggle: Bool {
        switch mode {
        case .create: return true
        case .edit(let m):
            return editingStatus == .planned && m.authorPartnerID != nil && m.authorPartnerID == myID
        }
    }
    private var visibilityLocked: Bool {
        guard let m = editingMeeting else { return false }
        return LedgerRules.isRevealed(visibilityRaw: m.visibilityRaw, revealedAt: m.revealedAt)
    }
```

2. 日期 GroupedSection 之后插入(Toggle 交互逐字照 TodoFormView 的私密 Toggle,含 confirmReveal 确认弹窗与脚注两态文案「已公开，不可改回私密」/「开着=公开前只有你看得到」,外层包 `if showsPrivacyToggle`;脚注多一句):

```swift
                    if showsPrivacyToggle {
                        GroupedSection {
                            Toggle("私密", isOn: Binding(
                                get: { visibility == .privateUntilRevealed },
                                set: { newValue in
                                    if !newValue, editingMeeting != nil, !visibilityLocked,
                                       visibility == .privateUntilRevealed {
                                        confirmReveal = true
                                    } else {
                                        visibility = newValue ? .privateUntilRevealed : .sharedImmediately
                                    }
                                }))
                                .disabled(visibilityLocked)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                        Text(visibilityLocked
                             ? "已公开，不可改回私密"
                             : "开着=公开前只有你看得到；点「开始见面」时会自动公开")
                            .dsFootnote().padding(.horizontal, 4)
                    }
```

3. `.alert("公开给 TA？", isPresented: $confirmReveal)`(按钮「公开」置 `visibility = .sharedImmediately`,message「公开后 TA 会看到这次计划，且不可撤回。」——TodoFormView 同款)。
4. `loadIfNeeded` 追加:

```swift
        visibility = visibilityLocked ? .sharedImmediately
            : (EntryVisibility(rawValue: m.visibilityRaw) ?? .sharedImmediately)
```

5. `save()` 改:

```swift
        switch mode {
        case .create(let couple):
            let authorID = CoupleRepository(context: context).currentPartnerID(of: couple)
            try? MeetingRepository(context: context).createPlanned(
                couple: couple, title: t, city: c, plannedStart: start, plannedEnd: end,
                authorID: authorID, visibility: visibility)
        case .edit(let m):
            try? MeetingRepository(context: context).update(
                m, title: t, city: c, start: start, end: end)
            // 编辑私密计划改公开 = 等效公开动作(TodoFormView 同款)
            if showsPrivacyToggle, !visibilityLocked, visibility == .sharedImmediately,
               m.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue {
                try? MeetingRepository(context: context).reveal(m, at: Date())
            }
        }
```

- [ ] **Step 5: 过滤面接线**

`MeetingsView`:

```swift
    private var myID: UUID? {
        couples.first.flatMap { CoupleRepository(context: context).currentPartnerID(of: $0) }
    }
    private var visibleMeetings: [CDMeeting] { meetings.filter { $0.isVisible(to: myID) } }
```

listContent 的 `ForEach(meetings…)` → `ForEach(visibleMeetings…)`;`meetings.isEmpty` 空态判断与 toolbar 的 `!meetings.isEmpty` → visibleMeetings;批量删除 `meetings.filter { selected.contains(...) }` → visibleMeetings。plannedCard 首行 footnote 改:

```swift
                HStack(spacing: 6) {
                    Text("第 \(meeting.index) 次见面 · 计划中").dsFootnote()
                    if meeting.isPrivateUnrevealed { MeetingPrivacyChip() }
                }
```

`PlanView` header(标题 Text 之下、倒计时 caption 同级):

```swift
            if meeting.isPrivateUnrevealed { MeetingPrivacyChip() }
```

(开始见面按钮零改动——T1 的 start 已自动公开。)

`HomeView.statusCard`:开头加 `let myID = CoupleRepository(context: context).currentPartnerID(of: couple)`;`let planned = try? repo.nextPlannedMeeting(...)` 整行替换为本地计算(带过滤,语义=原函数+可见性):

```swift
        let today = Calendar.current.startOfDay(for: Date())
        let planned = meetings
            .filter { $0.statusRaw == MeetingStatus.planned.rawValue && $0.isVisible(to: myID) }
            .filter { ($0.plannedStart ?? .distantFuture) >= today }
            .min { ($0.plannedStart ?? .distantFuture) < ($1.plannedStart ?? .distantFuture) }
```

`HomeView.todayCard`:把 `let myID = ...` 从 dueTodos 前挪到 planRows 之前,planRows 的 meetings 过滤链加一环:

```swift
            .filter { $0.statusRaw != MeetingStatus.finished.rawValue && $0.isVisible(to: myID) }
```

`PlacesMapView.hasActivePlan`:

```swift
    private func hasActivePlan(_ place: CDPlace) -> Bool {
        ((place.planItems as? Set<CDPlanItem>) ?? []).contains {
            guard $0.day != nil, let meeting = $0.meeting else { return false }
            return meeting.statusRaw != MeetingStatus.finished.rawValue
                && meeting.isVisible(to: myID)   // R17:私密计划的钉不能泄露(anyVisible 同理)
        }
    }
```

- [ ] **Step 6: 全仓 sweep 兜底**

Run: `grep -rn "MeetingStatus.planned" Features/ | grep -v Tests`
逐点核对:已改(MeetingsView/HomeView/PlacesMapView/MeetingFormView)、天然安全(CalendarView `guard let start = m.startedAt` 计划中不上带;DaySheet 走 dateDays 计划中无;PlanView 仅作者可达;MeetingRepository.nextPlannedMeeting 已无 Features 调用方)。发现遗漏浮现点一律补 `isVisible(to:)` 过滤并在提交信息注明。

- [ ] **Step 7: 测试至绿 + 提交**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 全绿,含 testPrivatePlannedMeetingVisibility;既有地图/时间线测试不受新增种子干扰(城市用了南京/杭州,列表锚「上海」仍唯一——若「还没有带地点的记忆」等断言受影响,查种子而非改断言)。

```bash
git add Features/Meetings/MeetingVisibility.swift Features/Meetings/MeetingFormView.swift Features/Meetings/MeetingsView.swift Features/Plan/PlanView.swift Features/Home/HomeView.swift Features/Places/PlacesMapView.swift Support/DebugSeeder.swift UITests/MapFilterReproTests.swift
git commit -m "R17-T6 私密计划:表单开关+🔒chip+列表/首页/地图全过滤面+种子与UI回归"
```
(新建 MeetingVisibility.swift → 提交前先 `./scripts/gen.sh`。)

---

### Task 7: 文档与全量收口

**Files:**
- Modify: `docs/RELEASE.md`

**Interfaces:**
- Consumes: 全部前置任务落地后的最终态。

- [ ] **Step 1: RELEASE.md 更新**

1. schema 部署步骤段追加一行(照 CDCycle.authorPartnerID 那条的写法):「R17:CD_Meeting 新增 authorPartnerID/visibilityRaw/revealedAt 三字段,CD_Evidence 新增 CD_todoItem 引用字段——开发环境真机跑一遍(建私密计划+待办加照片)生成 schema 后 Console Deploy。」
2. 验收清单追加:
   - 32 私密计划:A 机建私密计划 → B 机足迹列表/首页倒计时/今天卡/日历/地图计划钉全不可见;A 机计划卡带「🔒 私密」。
   - 33 私密公开:A 机表单关私密(确认弹窗)→ B 机计划出现;再进 A 表单私密开关锁定灰显。
   - 34 开始即公开:A 机私密计划直接「开始见面」→ B 机见面进行中可见,时间线正常。
   - 35 待办详情:任一方点待办行进详情(非编辑);作者「⋯」可编辑删除;照片加 9 张、详情横滑可看大图;带坐标地点「导航」跳高德/苹果地图。
   - 36 小本本详情导航:好事/生气/喜好详情地点行同 35 验证。
   - 37 完成开关:待办勾选圈连点多次,每次界面即时翻转。

- [ ] **Step 2: 全量门禁(单元 + 全部 UI 测试)**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: ✅构建通过 / ✅测试通过。任何红即回相应任务修复,不得跳过。

- [ ] **Step 3: 提交**

```bash
git add docs/RELEASE.md
git commit -m "R17-T7 收口:RELEASE 验收清单 32-37 + schema 部署步骤追加"
```
