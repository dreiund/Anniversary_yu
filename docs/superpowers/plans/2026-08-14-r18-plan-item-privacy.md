# R18 单条日程私密 + 日程照片 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 私密与照片下沉到单条行前日程(转化成回忆即自动公开、照片随转化带走),同时拆除 R17 的整趟见面私密 UI 与过滤。

**Architecture:** 数据层先行(CDPlanItem 两字段 + CDEvidence 第三父关系 + 仓库 API);随后一个纯拆除任务恢复见面级原貌;表单/查看页/转化预填一个任务;隐身面(时间线咽喉点+行前列表+今天卡+地图钉+统计口径)一个任务;种子与 UI 回归、文档收口各一。可见性判定一律 `LedgerRules.isVisible` 直调(视图层过滤,与小本本/待办同构)。

**Tech Stack:** SwiftUI + Core Data(程序化模型 ModelSchema)+ CloudKit;XcodeGen;XCTest/XCUITest。

**Spec:** `docs/superpowers/specs/2026-08-14-r18-plan-item-privacy-photos-design.md`(spec 为准;本计划从它论证)

## Global Constraints

- 新建 .swift 文件后必须先 `./scripts/gen.sh`(本轮无新源文件计划,若临时新建须记得)。
- 门禁:`./scripts/build.sh` 打印 ✅构建通过、`./scripts/test.sh` 打印 ✅测试通过;UI 测试用 `xcodebuild -only-testing:AnniversaryUITests/...`(模拟器 iPhone 17 Pro)单独跑。SourceKit 诊断是索引噪音。
- raw 值/字段只许追加,禁改禁删;文案全中文;DS token 禁硬编码颜色;UI 断言锚点用显式 accessibilityLabel 或唯一文案。
- 每个 commit 尾部带:`Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` 与 `Claude-Session: https://claude.ai/code/session_01QKnmr2idBpc7e7LJyhm1QR`。
- 备忘(day==nil)不参与私密与照片:表单备忘模式不渲染两段;备忘保存恒公开(既有私密日程被切成备忘保存=等效公开,走 reveal)。

---

### Task 1: 数据层——CDPlanItem 私密两字段 + 照片第三父关系 + 仓库 API

**Files:**
- Modify: `Domain/ModelSchema.swift`
- Modify: `Domain/ManagedObjects.swift`
- Modify: `Persistence/PlanItemRepository.swift`
- Test: `Tests/PlanItemRepositoryTests.swift`(追加)、`Tests/ModelSchemaTests.swift`(追加)

**Interfaces:**
- Consumes: `EntryVisibility`、`LedgerRules.isVisible`、`Thumbnailer.thumbnailData(from:)`、TodoRepository 的同款 evidence 三函数样式。
- Produces(后续任务依赖的确切签名):
  - `CDPlanItem.visibilityRaw: Int16`(非空默认 0)/ `CDPlanItem.revealedAt: Date?` / `CDPlanItem.evidences: NSSet?` / `CDEvidence.planItem: CDPlanItem?`
  - `PlanItemRepository.add(to:day:time:title:note:placeText:authorID:remindAt:place:visibility:)`(尾参 `visibility: EntryVisibility = .sharedImmediately`,既有调用零改动)
  - `PlanItemRepository.reveal(_ item: CDPlanItem, at date: Date) throws`(幂等)
  - `PlanItemRepository.evidencesSorted(_ item: CDPlanItem) -> [CDEvidence]` / `addEvidences(_ item: CDPlanItem, datas: [Data]) throws` / `deleteEvidence(_ evidence: CDEvidence) throws`
  - `PlanItemRepository.stats(for meeting: CDMeeting, visibleTo myID: UUID? = nil) -> (planned: Int, done: Int)`(nil=全量,旧调用点暂不破坏,Task 4 接线)

- [ ] **Step 1: 写失败测试**

`Tests/ModelSchemaTests.swift` 追加:

```swift
    func testR18PlanItemAdditions() {
        let model = ModelSchema.model
        let plan = model.entitiesByName["CDPlanItem"]!
        XCTAssertNotNil(plan.attributesByName["visibilityRaw"])
        XCTAssertFalse(plan.attributesByName["visibilityRaw"]!.isOptional)
        XCTAssertNotNil(plan.attributesByName["revealedAt"])
        let evidences = plan.relationshipsByName["evidences"]!
        XCTAssertEqual(evidences.destinationEntity?.name, "CDEvidence")
        XCTAssertEqual(evidences.deleteRule, .cascadeDeleteRule)
        XCTAssertEqual(model.entitiesByName["CDEvidence"]!
            .relationshipsByName["planItem"]!.inverseRelationship?.name, "evidences")
    }
```

`Tests/PlanItemRepositoryTests.swift` 追加(couple/meeting 夹具照本文件既有写法;若无现成 helper 就照文件里既有测试起头几行抄):

```swift
    func testAddDefaultsToSharedAndExplicitPrivate() throws {
        let repo = PlanItemRepository(context: context)
        let a = try repo.add(to: meeting, day: Date(), time: nil, title: "公开项",
                             note: nil, placeText: nil, authorID: nil)
        XCTAssertEqual(a.visibilityRaw, EntryVisibility.sharedImmediately.rawValue)
        let b = try repo.add(to: meeting, day: Date(), time: nil, title: "私密项",
                             note: nil, placeText: nil, authorID: nil,
                             visibility: .privateUntilRevealed)
        XCTAssertEqual(b.visibilityRaw, EntryVisibility.privateUntilRevealed.rawValue)
        XCTAssertNil(b.revealedAt)
    }

    func testRevealIsIdempotent() throws {
        let repo = PlanItemRepository(context: context)
        let item = try repo.add(to: meeting, day: Date(), time: nil, title: "x",
                                note: nil, placeText: nil, authorID: nil,
                                visibility: .privateUntilRevealed)
        let t1 = Date(timeIntervalSince1970: 100)
        try repo.reveal(item, at: t1)
        XCTAssertEqual(item.revealedAt, t1)
        try repo.reveal(item, at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(item.revealedAt, t1)   // 时戳留痕,不可覆盖
    }

    func testEvidenceAddSortDeleteCascade() throws {
        let repo = PlanItemRepository(context: context)
        let item = try repo.add(to: meeting, day: Date(), time: nil, title: "带照片",
                                note: nil, placeText: nil, authorID: nil)
        try repo.addEvidences(item, datas: [Data([0x1]), Data([0x2])])
        try repo.addEvidences(item, datas: [Data([0x3])])
        XCTAssertEqual(repo.evidencesSorted(item).map(\.sortIndex), [0, 1, 2])
        try repo.deleteEvidence(repo.evidencesSorted(item)[1])
        XCTAssertEqual(repo.evidencesSorted(item).count, 2)
        try repo.delete(item)
        let fetch = NSFetchRequest<CDEvidence>(entityName: "CDEvidence")
        XCTAssertEqual((try context.fetch(fetch)).count, 0)   // 删父级联删照片
    }

    /// 统计按观看者可见口径(spec §三.5):nil=全量;私密未公开只计作者侧
    func testStatsVisibleTo() throws {
        let repo = PlanItemRepository(context: context)
        let me = UUID(), other = UUID()
        _ = try repo.add(to: meeting, day: Date(), time: nil, title: "公开",
                         note: nil, placeText: nil, authorID: me)
        let mine = try repo.add(to: meeting, day: Date(), time: nil, title: "我的私密",
                                note: nil, placeText: nil, authorID: me,
                                visibility: .privateUntilRevealed)
        try repo.toggleDone(mine)
        XCTAssertEqual(repo.stats(for: meeting).planned, 2)            // nil=全量
        XCTAssertEqual(repo.stats(for: meeting, visibleTo: me).planned, 2)
        XCTAssertEqual(repo.stats(for: meeting, visibleTo: me).done, 1)
        XCTAssertEqual(repo.stats(for: meeting, visibleTo: other).planned, 1)  // 对方看不见我的私密
        XCTAssertEqual(repo.stats(for: meeting, visibleTo: other).done, 0)
        try repo.reveal(mine, at: Date())
        XCTAssertEqual(repo.stats(for: meeting, visibleTo: other).planned, 2)  // 公开后计入
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh 2>&1 | tail -15`
Expected: 编译失败(add 无 visibility 参、CDPlanItem 无 visibilityRaw 等)——编译失败即失败测试成立。

- [ ] **Step 3: 实现模型增量**

`Domain/ModelSchema.swift`:planItem 实体属性表尾部追加两行:

```swift
            attr("visibilityRaw", .integer16AttributeType, optional: false, defaultValue: 0),  // R18 日程私密
            attr("revealedAt", .dateAttributeType),
```

关系区(挨着 todo 的 evidences 行)追加:

```swift
        oneToMany(planItem, "evidences", evidence, "planItem")
```

`Domain/ManagedObjects.swift`:CDPlanItem 追加 `@NSManaged var visibilityRaw: Int16`、`@NSManaged var revealedAt: Date?`、`@NSManaged var evidences: NSSet?`;CDEvidence 追加 `@NSManaged var planItem: CDPlanItem?`。

- [ ] **Step 4: 实现仓库 API**

`Persistence/PlanItemRepository.swift`:

1. `add(...)` 签名尾部追加 `visibility: EntryVisibility = .sharedImmediately`,创建体在 `item.place = place` 前加一行 `item.visibilityRaw = visibility.rawValue`。
2. 追加(照 TodoRepository 同款,不抽公共层——spec §四既有先例):

```swift
    /// 公开仪式:一次性置戳(同小本本 reveal 语义),不碰 visibilityRaw
    func reveal(_ item: CDPlanItem, at date: Date) throws {
        guard item.revealedAt == nil else { return }
        item.revealedAt = date
        try context.save()
    }

    func evidencesSorted(_ item: CDPlanItem) -> [CDEvidence] {
        ((item.evidences as? Set<CDEvidence>) ?? [])
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func addEvidences(_ item: CDPlanItem, datas: [Data]) throws {
        let start = (evidencesSorted(item).last?.sortIndex).map { $0 + 1 } ?? 0
        for (i, data) in datas.enumerated() {
            let evidence = CDEvidence(context: context)
            evidence.id = UUID()
            evidence.imageData = data
            evidence.thumbnailData = Thumbnailer.thumbnailData(from: data)
            evidence.sortIndex = start + Int32(i)
            evidence.planItem = item
        }
        try context.save()
    }

    func deleteEvidence(_ evidence: CDEvidence) throws {
        context.delete(evidence)
        try context.save()
    }
```

3. `stats(for:)` 改为(默认参零破坏):

```swift
    /// R18 spec §三.5:统计按观看者可见口径(nil=全量;私密未公开只计作者)
    func stats(for meeting: CDMeeting, visibleTo myID: UUID? = nil) -> (planned: Int, done: Int) {
        var all = Array(((meeting.planItems as? Set<CDPlanItem>) ?? []))
        if let myID {
            all = all.filter {
                LedgerRules.isVisible(authorID: $0.authorPartnerID, myID: myID,
                                      visibilityRaw: $0.visibilityRaw, revealedAt: $0.revealedAt)
            }
        }
        return (all.count, all.filter(\.isDone).count)
    }
```

注:Persistence 引用 Features/Ledger 的 LedgerRules 在本仓已有先例风险——若编译分层报错(实际同 target 无模块边界,不会),就地内联同构判定并注明。

- [ ] **Step 5: 门禁绿 + 提交**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 全绿(默认参保证既有调用零破坏)。

```bash
git add Domain/ModelSchema.swift Domain/ManagedObjects.swift Persistence/PlanItemRepository.swift Tests/PlanItemRepositoryTests.swift Tests/ModelSchemaTests.swift
git commit -m "R18-T1 数据层:日程私密两字段+照片第三父关系+reveal/evidence/统计可见口径"
```

---

### Task 2: 拆除整趟见面私密(1B)

**Files:**
- Modify: `Features/Meetings/MeetingFormView.swift`
- Modify: `Features/Meetings/MeetingsView.swift`
- Modify: `Features/Plan/PlanView.swift`
- Modify: `Features/Home/HomeView.swift`
- Modify: `Features/Places/PlacesMapView.swift`
- Modify: `Support/DebugSeeder.swift`
- Modify: `UITests/MapFilterReproTests.swift`
- Delete: `Features/Meetings/MeetingVisibility.swift`

**Interfaces:**
- Consumes: R17 落的这些改动(逐处还原);`MeetingRepository.nextPlannedMeeting(couple:after:)`(仍在仓库)。
- Produces: 见面级私密 UI/过滤全无;CDMeeting 三字段与 MeetingRepository.reveal/start 自动公开保留(spec §一);Tests/MeetingPrivacyTests.swift 不动。

- [ ] **Step 1: 逐文件拆除**

1. `MeetingFormView.swift`:删 `@State visibility`/`confirmReveal`、`myID`/`showsPrivacyToggle`/`visibilityLocked` 计算属性、`if showsPrivacyToggle { ... }` 整段(GroupedSection+脚注)、`.alert("公开给 TA？"...)`、loadIfNeeded 里 visibility 行;save() 恢复为:

```swift
        switch mode {
        case .create(let couple):
            try? MeetingRepository(context: context).createPlanned(
                couple: couple, title: t, city: c, plannedStart: start, plannedEnd: end)
        case .edit(let m):
            try? MeetingRepository(context: context).update(
                m, title: t, city: c, start: start, end: end)
        }
```

2. `MeetingsView.swift`:删 `myID`/`visibleMeetings`,ForEach/空态/toolbar/批量删除恢复用 `meetings`;plannedCard 首行恢复为单个 `Text("第 \(meeting.index) 次见面 · 计划中").dsFootnote()`(去 HStack+chip)。
3. `PlanView.swift`:header 里 `if meeting.isPrivateUnrevealed { MeetingPrivacyChip() }` 删除。
4. `HomeView.swift` statusCard:本地 planned 计算三行删除,恢复 `let planned = try? repo.nextPlannedMeeting(couple: couple, after: Calendar.current.startOfDay(for: Date()))`;statusCard 顶部的 `let myID = ...` 保留(Task 4 统计接线要用)。todayCard:planRows 的 meetings 过滤链去掉 `&& $0.isVisible(to: myID)`(恢复只滤 finished;myID 声明位置不动,Task 4 用)。
5. `PlacesMapView.swift` hasActivePlan:去掉 `&& meeting.isVisible(to: myID)`(恢复 R17 前原状;Task 4 换成条目级)。
6. 删除文件 `Features/Meetings/MeetingVisibility.swift`(`git rm`)。
7. `DebugSeeder.swift`:删除 R17 的两条私密见面种子(「演示惊喜」「演示他方私密」整段)。
8. `UITests/MapFilterReproTests.swift`:整个 `testPrivatePlannedMeetingVisibility` 删除(Task 5 出日程级替代)。

- [ ] **Step 2: 全仓残留检查**

Run: `grep -rn "isPrivateUnrevealed\|MeetingPrivacyChip\|isVisible(to:" Features/ Support/ UITests/`
Expected: 零命中(有命中=漏拆,回 Step 1)。

- [ ] **Step 3: 门禁绿 + 提交**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 全绿(MeetingPrivacyTests 仍绿——仓库 API 未动)。

```bash
git add -A
git commit -m "R18-T2 拆除整趟见面私密(1B):表单开关/chip/过滤/种子/旧UI测试还原,字段与仓库API保留兜底"
```

---

### Task 3: 日程表单照片+私密 + 查看页照片 + 转化预填

**Files:**
- Modify: `Features/Plan/PlanItemFormSheet.swift`
- Modify: `Features/Plan/PlanItemDetailSheet.swift`
- Modify: `Features/Moments/MomentFormView.swift`

**Interfaces:**
- Consumes: T1 `add(visibility:)`/`reveal`/`evidencesSorted`/`addEvidences`/`deleteEvidence`;`EvidenceViewer`(internal)/`EvidenceIndex`;LedgerFormView 的 PhotosPicker 范式;`LedgerRules.isRevealed`。
- Produces: 日程模式表单带「照片」「私密」两段;查看页照片区+可见性行;`.fromPlan` 预填照片(3A)。

- [ ] **Step 1: PlanItemFormSheet 加两段(仅 formMode == .schedule 渲染)**

1. `import PhotosUI`;状态追加:

```swift
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photoDatas: [Data] = []
    @State private var evidencesToDelete: [CDEvidence] = []
    @State private var visibility: EntryVisibility = .sharedImmediately
    @State private var confirmReveal = false
```

2. 计算属性:

```swift
    private var existingEvidences: [CDEvidence] {
        guard let item else { return [] }
        return PlanItemRepository(context: context).evidencesSorted(item)
            .filter { !evidencesToDelete.contains($0) }
    }
    /// 已公开条目锁定(同小本本口径)
    private var visibilityLocked: Bool {
        guard let item else { return false }
        return LedgerRules.isRevealed(visibilityRaw: item.visibilityRaw, revealedAt: item.revealedAt)
    }
```

3. 备注 GroupedSection 之后追加两段(整体包 `if formMode == .schedule`):照片段照 LedgerFormView 同款(PhotosPicker maxSelectionCount 9、label「照片」、52pt 缩略横排含 existingEvidences+photoDatas、`evidenceThumb(_:)` 与 `.onChange(of: pickerItems)` 逐字照 LedgerFormView 同名实现复制);私密段:

```swift
                    if formMode == .schedule {
                        GroupedSection {
                            Toggle("私密", isOn: Binding(
                                get: { visibility == .privateUntilRevealed },
                                set: { newValue in
                                    if !newValue, item != nil, !visibilityLocked,
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
                             : "开着=公开前只有你看得到；转化成回忆的那一刻会自动公开")
                            .dsFootnote().padding(.horizontal, 4)
                    }
```

4. `.alert("公开给 TA？", isPresented: $confirmReveal)`(「公开」置 `visibility = .sharedImmediately`;message「公开后 TA 会看到这条日程，且不可撤回。」)。
5. `loadIfEditing()` 追加:

```swift
        visibility = visibilityLocked ? .sharedImmediately
            : (EntryVisibility(rawValue: item.visibilityRaw) ?? .sharedImmediately)
```

- [ ] **Step 2: save() 接线**

新建分支 `repo.add(...)` 尾部传 `visibility: isMemo ? .sharedImmediately : visibility`。编辑分支(`if let item` 内,update 之后)追加:

```swift
            // 编辑关私密=等效公开;既有私密日程切成备忘保存=恒公开(spec §五)
            if !visibilityLocked,
               item.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue,
               isMemo || visibility == .sharedImmediately {
                try? repo.reveal(item, at: Date())
            }
```

照片落库(savedItem 赋值后、提醒排程前):

```swift
        if formMode == .schedule {
            for evidence in evidencesToDelete { try? repo.deleteEvidence(evidence) }
            if !photoDatas.isEmpty, let savedItem { try? repo.addEvidences(savedItem, datas: photoDatas) }
        }
```

- [ ] **Step 3: PlanItemDetailSheet 照片区 + 可见性行**

地点/placeText 段之后、备注段之前插入:

```swift
                    if item.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue {
                        GroupedSection {
                            HStack {
                                Text("可见性").dsBody()
                                Spacer()
                                Text(item.revealedAt.map { "\(Fmt.monthDay.string(from: $0)) 已公开" }
                                     ?? "仅自己可见 🔒")
                                    .dsCaption()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                    }
                    let evidences = PlanItemRepository(context: context).evidencesSorted(item)
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
                                .padding(.horizontal, 2).padding(.vertical, 8)
                            }
                        }
                    }
```

状态 `@State private var viewerIndex: Int?` + modifier 链追加(照 TodoDetailView 同款):

```swift
            .fullScreenCover(item: Binding(
                get: { viewerIndex.map { EvidenceIndex(id: $0) } },
                set: { viewerIndex = $0?.id })) { index in
                EvidenceViewer(evidences: PlanItemRepository(context: context).evidencesSorted(item),
                               index: index.id)
            }
```

- [ ] **Step 4: MomentFormView 转化预填照片(3A)**

`.fromPlan` 的 loadIfEditing 分支(`type = .other` 之前任意位置、`return` 之前)追加:

```swift
            // R18 3A:日程照片随转化带进回忆(转化删源会级联删日程照片,不带走就丢了)
            photoDatas = repo.evidencesSorted(item).compactMap(\.imageData)
```

- [ ] **Step 5: 门禁绿 + 提交**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 全绿。

```bash
git add Features/Plan/PlanItemFormSheet.swift Features/Plan/PlanItemDetailSheet.swift Features/Moments/MomentFormView.swift
git commit -m "R18-T3 日程表单照片+私密开关(仅日程模式)+查看页照片区+转化预填带走"
```

---

### Task 4: 隐身面全接线 + 行内标识

**Files:**
- Modify: `Features/Meetings/TimelineListView.swift`
- Modify: `Features/Plan/PlanView.swift`
- Modify: `Features/Home/HomeView.swift`
- Modify: `Features/Places/PlacesMapView.swift`
- Modify: `Features/Meetings/MeetingsView.swift`
- Modify: `Features/Meetings/PlanCardViews.swift`

**Interfaces:**
- Consumes: T1 `stats(for:visibleTo:)`/`evidencesSorted`;`LedgerRules.isVisible`。
- Produces: 对方私密日程在行前列表/时间线四组/今天卡/地图计划钉/三处统计全隐;自己侧行尾 🔒 + 22pt 首图缩略。

- [ ] **Step 1: TimelineListView 咽喉点过滤**

顶部加 couples 查询与 body 内 myID(既有文件无 couples fetch):

```swift
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDCouple.createdAt)]) private var couples: FetchedResults<CDCouple>
```

body 里 `let allPlans = showPlans ? Array(plansFetch) : []` 改为:

```swift
        let myID = couples.first.flatMap { CoupleRepository(context: context).currentPartnerID(of: $0) }
        // R18 隐身面单一咽喉点:对方私密日程在已备/散插/tail/灰卡(乃至备忘)全体隐形
        let allPlans = (showPlans ? Array(plansFetch) : []).filter {
            LedgerRules.isVisible(authorID: $0.authorPartnerID, myID: myID,
                                  visibilityRaw: $0.visibilityRaw, revealedAt: $0.revealedAt)
        }
```

- [ ] **Step 2: PlanView 列表过滤 + 统计接线**

content 顶部(repo 之后)加:

```swift
        let myID = couples.first.flatMap { CoupleRepository(context: context).currentPartnerID(of: $0) }
```

(文件顶部同样补 couples FetchRequest,同 Step 1 写法。)`sections`/`stats` 两行改为:

```swift
        let raw = repo.sections(for: meeting, calendar: .current)
        let isVisible: (CDPlanItem) -> Bool = {
            LedgerRules.isVisible(authorID: $0.authorPartnerID, myID: myID,
                                  visibilityRaw: $0.visibilityRaw, revealedAt: $0.revealedAt)
        }
        let sections = PlanSections(
            dated: raw.dated.map { ($0.day, $0.items.filter(isVisible)) }.filter { !$0.items.isEmpty },
            undated: raw.undated.filter(isVisible))
        let stats = repo.stats(for: meeting, visibleTo: myID)
```

- [ ] **Step 3: HomeView 两处接线**

statusCard:`let stats = PlanItemRepository(context: context).stats(for: planned)` → `stats(for: planned, visibleTo: myID)`。todayCard:planRows 内层 planItems 过滤链加条目级判定:

```swift
                (((meeting.planItems as? Set<CDPlanItem>) ?? []))
                    .filter { LedgerRules.isVisible(authorID: $0.authorPartnerID, myID: myID,
                                                    visibilityRaw: $0.visibilityRaw, revealedAt: $0.revealedAt) }
                    .filter { $0.day.map { Calendar.current.isDate($0, inSameDayAs: today) } ?? false }
```

- [ ] **Step 4: PlacesMapView + MeetingsView**

`hasActivePlan` 改条目级:

```swift
    private func hasActivePlan(_ place: CDPlace) -> Bool {
        ((place.planItems as? Set<CDPlanItem>) ?? []).contains {
            guard $0.day != nil, let meeting = $0.meeting else { return false }
            // R18:私密日程的地点不成计划钉(anyVisible 防泄露先例)
            return meeting.statusRaw != MeetingStatus.finished.rawValue
                && LedgerRules.isVisible(authorID: $0.authorPartnerID, myID: myID,
                                         visibilityRaw: $0.visibilityRaw, revealedAt: $0.revealedAt)
        }
    }
```

MeetingsView plannedCard:`let stats = PlanItemRepository(context: context).stats(for: meeting)` → `stats(for: meeting, visibleTo: myID)`,并在 MeetingsView 补回:

```swift
    private var myID: UUID? {
        couples.first.flatMap { CoupleRepository(context: context).currentPartnerID(of: $0) }
    }
```

(T2 删过它;此处仅为统计口径回来,不再有 visibleMeetings。)

- [ ] **Step 5: 行内标识(自己侧)**

`PlanCardViews.swift` PlanTodoCard:subtitle parts 组装里、时间 part 之后插:

```swift
        if item.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue, item.revealedAt == nil {
            parts.append("🔒")
        }
```

Spacer 之后(missed 徽标之前)加缩略:

```swift
            if let thumb = PlanItemRepository(context: context).evidencesSorted(item).first?.thumbnailData,
               let ui = UIImage(data: thumb) {
                Image(uiImage: ui).resizable().scaledToFill()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .allowsHitTesting(false)
            }
```

`PlanView.swift` 的 planRow(日程行 builder,读文件定位):行内时间/标题后同样加 🔒 小字(`Text("🔒").font(.system(size: 11))`,判定同上)与行尾 22pt 缩略(同上代码,Spacer 后)。

- [ ] **Step 6: sweep 兜底 + 门禁 + 提交**

Run: `grep -rn "planItems as? Set" Features/ | grep -v Tests`
逐点核对:已接(TimelineListView 经 plansFetch 咽喉/PlanView 经 sections/HomeView todayCard/PlacesMapView hasActivePlan/stats 经 visibleTo)、天然安全(MeetingsView 批量删除的 planItems 取 id 仅用于取消提醒——删的是整个见面,作者自己操作,无泄露;MomentFormView/PlanItemFormSheet 表单自读)。遗漏一律补判定并在提交信息注明。

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 全绿。

```bash
git add Features/Meetings/TimelineListView.swift Features/Plan/PlanView.swift Features/Home/HomeView.swift Features/Places/PlacesMapView.swift Features/Meetings/MeetingsView.swift Features/Meetings/PlanCardViews.swift
git commit -m "R18-T4 隐身面:时间线咽喉点+行前列表+今天卡+计划钉+统计可见口径;行内🔒与缩略"
```

---

### Task 5: 种子 + UI 回归测试

**Files:**
- Modify: `Support/DebugSeeder.swift`
- Test: `UITests/MapFilterReproTests.swift`(追加)

**Interfaces:**
- Consumes: T1-T4 全部落地;种子既有 `myID`/`herID`/`day(_:)`/`solidImageData(_:)`。
- Produces: 种子含公开计划见面「演示行前」+ 三条日程(公开/我方私密带照片/对方私密);`testPrivatePlanItemVisibility`。

- [ ] **Step 1: 种子追加(记得做种子之后,R17 见面种子已在 T2 删除)**

```swift
        // R18 日程级私密种子:公开计划见面 + 公开项/我方私密带照片/对方私密(全隐验证样本)
        if let trip = try? meetings.createPlanned(couple: couple, title: "演示行前", city: "南京",
                                                  plannedStart: day(20), plannedEnd: day(22)) {
            let planRepo = PlanItemRepository(context: context)
            _ = try? planRepo.add(to: trip, day: day(20), time: nil, title: "取门票",
                                  note: nil, placeText: nil, authorID: myID)
            if let secret = try? planRepo.add(to: trip, day: day(20), time: nil, title: "惊喜环节",
                                              note: nil, placeText: nil, authorID: myID,
                                              visibility: .privateUntilRevealed) {
                try? planRepo.addEvidences(secret, datas: [solidImageData(.systemIndigo)].compactMap { $0 })
            }
            _ = try? planRepo.add(to: trip, day: day(21), time: nil, title: "演示他方私密项",
                                  note: nil, placeText: nil, authorID: herID,
                                  visibility: .privateUntilRevealed)
        }
```

(注:solidImageData 返回 Data?——照实际签名处理可选;若为非可选就直接传数组。)

- [ ] **Step 2: 写 UI 测试(先跑确认失败再全绿)**

```swift
    /// R18 §三:单条日程私密——我的带🔒可见,对方的全隐,计数按可见口径;表单开关在编辑里
    @MainActor
    func testPrivatePlanItemVisibility() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()

        app.buttons["足迹"].tap()
        let card = app.staticTexts["南京 · 演示行前"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), "计划卡未出现")
        // 本机视角可见=取门票+惊喜环节(对方私密项隐形)→ 计数 0/2
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "行前计划 0/2")).firstMatch.exists,
            "计数应按可见口径 0/2")
        card.tap()

        XCTAssertTrue(app.staticTexts["取门票"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["惊喜环节"].exists, "我的私密项该可见")
        XCTAssertTrue(app.staticTexts["🔒"].firstMatch.exists, "私密项缺🔒标识")
        XCTAssertFalse(app.staticTexts["演示他方私密项"].exists, "对方的私密项不该出现")

        // 点行进查看页:可见性行 + 照片区;编辑表单私密开关开
        app.staticTexts["惊喜环节"].tap()
        XCTAssertTrue(app.staticTexts["仅自己可见 🔒"].waitForExistence(timeout: 5), "查看页缺可见性行")
        XCTAssertTrue(app.staticTexts["照片"].exists, "查看页缺照片区")
        app.navigationBars.buttons["编辑"].tap()
        let toggle = app.switches["私密"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "日程表单缺私密开关")
        XCTAssertEqual(toggle.value as? String, "1", "私密开关应为开")
        app.buttons["取消"].tap()
    }
```

注:行进查看页的入口:PlanView 点行为查看(viewingItem→PlanItemDetailSheet,R9 行为);若点击被行内其他控件吃掉,改 tap 行的 staticText 坐标并说明。

- [ ] **Step 3: 跑测试(先失败态记录——Step 1 种子没进 Step 2 断言前预期红)+ 修至绿 + 全量门禁**

Run: `-only-testing:AnniversaryUITests/MapFilterReproTests/testPrivatePlanItemVisibility`(iPhone 17 Pro),再 `./scripts/build.sh && ./scripts/test.sh`,再全类 UI:`-only-testing:AnniversaryUITests`。
Expected: 新测试绿;既有 UI 测试不受新种子干扰(南京卡在列表新增——若「上海」锚位测试受影响,查种子而非改断言)。

- [ ] **Step 4: 提交**

```bash
git add Support/DebugSeeder.swift UITests/MapFilterReproTests.swift
git commit -m "R18-T5 种子(演示行前三件套)+日程私密UI回归"
```

---

### Task 6: 文档收口

**Files:**
- Modify: `docs/RELEASE.md`

**Interfaces:**
- Consumes: 最终代码态。

- [ ] **Step 1: RELEASE.md 更新**

1. schema 部署行(R17 那行里)追加:「;R18 增 CD_PlanItem.visibilityRaw/revealedAt 与 CD_Evidence 的 CD_planItem 引用——与 R17 字段合并为同一次部署」。
2. 验收清单 32-34 重写为日程口径、35 追加照片句:
   - 32 私密日程:A 机在计划见面里建私密日程 → B 机行前列表/时间线/今天卡/地图计划钉/「行前计划 x/y」计数全不含它;A 机行尾见 🔒。
   - 33 手动公开:A 机编辑该日程关掉私密(确认弹窗)→ B 机该日程出现;A 机再进编辑,开关锁定灰显。
   - 34 转化即公开:见面进行中 A 机把私密日程转化成回忆 → B 机时间线立刻可见该回忆(含照片);私密日程本体消失。
   - 35 行尾追加:「;日程照片:表单加 9 张、查看页横滑大图、转化后照片随回忆」。

- [ ] **Step 2: 全量门禁 + 提交**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 全绿。

```bash
git add docs/RELEASE.md
git commit -m "R18-T6 收口:RELEASE 验收 32-35 改日程口径+schema 部署行合并"
```
