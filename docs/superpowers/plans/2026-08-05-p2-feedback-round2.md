# P2 反馈②轮实现计划（解绑 / 昵称归属 / 见面改删 / 心情标名）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地四条真机反馈：双向「解除配对」、昵称严格各改各的（含受邀方加入确认页）、见面三态可改删限计划中（删后重编号）、首页心情卡标注作者。

**Architecture:** 全部在既有结构上扩展：MeetingRepository 加 update/deletePlanned；SharingManager 加 pairingStatus 纯函数 + unpair/leaveSpace 薄层；RootView 插入受邀方加入确认页分支；SettingsView 配对区按四态规则表重写。无新依赖、无模型迁移。

**Tech Stack:** SwiftUI + Core Data(NSPersistentCloudKitContainer 双 store) + CloudKit CKShare + XCTest + XcodeGen。

**Spec:** `docs/superpowers/specs/2026-08-05-p2-feedback-round2-design.md`（唯一权威，含状态表与文案）。

## Global Constraints

- deployment target **iOS 17.0**（女友 17.3.1；禁用 iOS 18 独占 API）
- 新建 .swift 文件后必须先 `./scripts/gen.sh`（XcodeGen 按目录收源文件），再 `./scripts/build.sh` / `./scripts/test.sh`，以输出 `✅ 构建通过` / `✅ 测试通过` 为准
- 唯一行动蓝 #0066CC（DS.actionBlue）；按钮文案 ≤6 字、不含 emoji；全部中文文案照抄本计划，不得改写
- `categoryRaw` 禁止写入（P3 才定枚举）
- 观察惯用法 `let _ = (…count…)` 是 FetchRequest 依赖注册，勿当死代码清理
- 每任务独立 commit（中文信息）；测试先行（TDD），UI 任务以构建 + 全量测试绿为门

---

### Task 1: MeetingRepository 三态更新与计划删除（含重编号）

**Files:**
- Modify: `Persistence/MeetingRepository.swift`（文件尾新增 extension）
- Test: `Tests/MeetingEditTests.swift`（新建）

**Interfaces:**
- Consumes: 既有 `MeetingRepository.status(of:)/createPlanned/start/end`、`CDMeeting.planItems`（Set<CDPlanItem>）、`CDMeeting.couple.meetings`
- Produces（T2 依赖，签名照抄）:
  - `enum MeetingRepository.EditError: Error { case notPlanned }`
  - `func update(_ meeting: CDMeeting, title: String?, city: String?, start: Date?, end: Date?) throws`
  - `func deletePlanned(_ meeting: CDMeeting) throws`

- [ ] **Step 1: 写失败测试**（新建 `Tests/MeetingEditTests.swift`，全文如下）

```swift
import XCTest
@testable import Anniversary

final class MeetingEditTests: XCTestCase {
    private func makeCouple() throws -> (PersistenceController, CDCouple) {
        let pc = PersistenceController(inMemory: true)
        let couple = try CoupleRepository(context: pc.viewContext)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        return (pc, couple)
    }

    func testUpdatePlannedWritesPlannedDates() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: "旧", city: "上海",
                                       plannedStart: Date(timeIntervalSince1970: 100),
                                       plannedEnd: Date(timeIntervalSince1970: 200))
        try repo.update(m, title: "新", city: nil,
                        start: Date(timeIntervalSince1970: 300),
                        end: Date(timeIntervalSince1970: 400))
        XCTAssertEqual(m.title, "新")
        XCTAssertNil(m.city)
        XCTAssertEqual(m.plannedStart, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(m.plannedEnd, Date(timeIntervalSince1970: 400))
        XCTAssertNil(m.startedAt)
    }

    func testUpdateOngoingWritesStartedAtOnly() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil,
                                       plannedStart: Date(timeIntervalSince1970: 100), plannedEnd: nil)
        try repo.start(m, at: Date(timeIntervalSince1970: 500))
        try repo.update(m, title: "改题", city: "杭州",
                        start: Date(timeIntervalSince1970: 600),
                        end: Date(timeIntervalSince1970: 700))
        XCTAssertEqual(m.startedAt, Date(timeIntervalSince1970: 600))
        XCTAssertNil(m.endedAt)                                    // ongoing 不写结束
        XCTAssertEqual(m.plannedStart, Date(timeIntervalSince1970: 100))  // 计划日期不动
    }

    func testUpdateFinishedWritesStartedAndEnded() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil,
                                       plannedStart: nil, plannedEnd: nil)
        try repo.start(m, at: Date(timeIntervalSince1970: 500))
        try repo.end(m, at: Date(timeIntervalSince1970: 900))
        try repo.update(m, title: nil, city: nil,
                        start: Date(timeIntervalSince1970: 550),
                        end: Date(timeIntervalSince1970: 950))
        XCTAssertEqual(m.startedAt, Date(timeIntervalSince1970: 550))
        XCTAssertEqual(m.endedAt, Date(timeIntervalSince1970: 950))
    }

    func testDeletePlannedCascadesItemsAndRenumbers() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m1 = try repo.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        try repo.start(m1, at: Date(timeIntervalSince1970: 100))
        try repo.end(m1, at: Date(timeIntervalSince1970: 200))     // idx1 已结束
        let m2 = try repo.createPlanned(couple: couple, title: "要删", city: nil, plannedStart: nil, plannedEnd: nil)
        let item = CDPlanItem(context: pc.viewContext)
        item.id = UUID(); item.title = "买票"; item.meeting = m2
        let m3 = try repo.createPlanned(couple: couple, title: "殿后", city: nil, plannedStart: nil, plannedEnd: nil)
        try pc.viewContext.save()

        try repo.deletePlanned(m2)

        let meetings = try repo.meetingsSorted(couple: couple)
        XCTAssertEqual(meetings.count, 2)
        XCTAssertEqual(m1.index, 1)
        XCTAssertEqual(m3.index, 2)                                // 不论状态整体前移
        let items = try pc.viewContext.fetch(CDPlanItem.fetchRequest())
        XCTAssertTrue(items.isEmpty)                               // 日程级联删除
    }

    func testDeleteNonPlannedThrows() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        try repo.start(m, at: Date(timeIntervalSince1970: 100))
        XCTAssertThrowsError(try repo.deletePlanned(m))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/gen.sh && ./scripts/test.sh`
Expected: 编译失败（`update`/`deletePlanned` 未定义）

- [ ] **Step 3: 最小实现**（`Persistence/MeetingRepository.swift` 文件尾追加）

```swift
extension MeetingRepository {
    enum EditError: Error { case notPlanned }

    /// 三态可改基本信息：日期按状态落位（planned→计划日期对；ongoing→仅 startedAt；finished→startedAt+endedAt）
    func update(_ meeting: CDMeeting, title: String?, city: String?,
                start: Date?, end: Date?) throws {
        meeting.title = title
        meeting.city = city
        switch status(of: meeting) {
        case .planned:
            meeting.plannedStart = start
            meeting.plannedEnd = end
        case .ongoing:
            meeting.startedAt = start ?? meeting.startedAt
        case .finished:
            meeting.startedAt = start ?? meeting.startedAt
            meeting.endedAt = end ?? meeting.endedAt
        }
        try context.save()
    }

    /// 仅计划中可删；级联删行前计划项；其后所有见面（不论状态）序号 -1 保持连续——
    /// 没发生过的计划被拿掉后，后面那次在现实里就是第 N-1 次见面。
    func deletePlanned(_ meeting: CDMeeting) throws {
        guard status(of: meeting) == .planned else { throw EditError.notPlanned }
        let couple = meeting.couple
        let removedIndex = meeting.index
        ((meeting.planItems as? Set<CDPlanItem>) ?? []).forEach(context.delete)
        context.delete(meeting)
        ((couple?.meetings as? Set<CDMeeting>) ?? [])
            .filter { $0.index > removedIndex }
            .forEach { $0.index -= 1 }
        try context.save()
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `./scripts/test.sh`
Expected: `✅ 测试通过`（全量，含既有 63 项）

- [ ] **Step 5: Commit**

```bash
git add Persistence/MeetingRepository.swift Tests/MeetingEditTests.swift
git commit -m "见面仓库：三态更新与计划删除，删后全体序号前移"
```

---

### Task 2: 见面表单双模式 + 编辑入口 + 删除按钮

**Files:**
- Modify: `Features/Meetings/MeetingFormView.swift`（整文件重写，下方全文）
- Modify: `Features/Meetings/MeetingsView.swift:30`（调用点改 `.create`）
- Modify: `Features/Plan/PlanView.swift`（toolbar 编辑 + 删除失效守卫）
- Modify: `Features/Meetings/MeetingDetailView.swift`（非计划态 toolbar 编辑）

**Interfaces:**
- Consumes: T1 的 `update(_:title:city:start:end:)`、`deletePlanned(_:)`；既有 `MeetingRepository.status(of:)`、`MomentFormMode` 先例（命名对齐）
- Produces: `enum MeetingFormMode { case create(CDCouple); case edit(CDMeeting) }`；`MeetingFormView(mode:)`（旧 `MeetingFormView(couple:)` 移除，全工程仅 MeetingsView 一处调用）

- [ ] **Step 1: 重写 `Features/Meetings/MeetingFormView.swift`（全文替换）**

```swift
import SwiftUI

enum MeetingFormMode {
    case create(CDCouple)
    case edit(CDMeeting)
}

struct MeetingFormView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let mode: MeetingFormMode
    @State private var title = ""
    @State private var city = ""
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Calendar.current.startOfDay(for: Date())
    @State private var loaded = false
    @State private var confirmDelete = false

    private var editingMeeting: CDMeeting? {
        if case .edit(let m) = mode { return m }
        return nil
    }

    private var editingStatus: MeetingStatus {
        editingMeeting.map { MeetingRepository(context: context).status(of: $0) } ?? .planned
    }

    /// 进行中只有实际开始可改（还没结束，无结束日期可言）
    private var showsEndDate: Bool { editingStatus != .ongoing }

    private var dateLabels: (start: String, end: String) {
        editingStatus == .planned ? ("开始日期", "结束日期") : ("实际开始", "实际结束")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.md) {
                    GroupedSection {
                        HStack {
                            Text("标题").dsBody()
                            TextField("可选，如 上海行", text: $title).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        HStack {
                            Text("城市").dsBody()
                            TextField("可选", text: $city).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        DatePicker(dateLabels.start, selection: $start, displayedComponents: .date)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                        if showsEndDate {
                            DS.hairline.frame(height: 1).padding(.leading, 14)
                            DatePicker(dateLabels.end, selection: $end, in: start..., displayedComponents: .date)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                        }
                    }

                    if editingMeeting != nil, editingStatus == .planned {
                        GroupedSection {
                            Button { confirmDelete = true } label: {
                                Text("删除这次计划").dsBody()
                                    .foregroundStyle(DS.dsRed)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                            }
                            .buttonStyle(DSPressEffect())
                        }
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle(editingMeeting == nil ? "计划见面" : "编辑见面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .confirmationDialog("删除这次计划？行前计划的日程会一起删除。",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除计划", role: .destructive) {
                    if let m = editingMeeting {
                        try? MeetingRepository(context: context).deletePlanned(m)
                    }
                    dismiss()
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private func loadIfNeeded() {
        guard !loaded, let m = editingMeeting else { return }
        loaded = true
        title = m.title ?? ""
        city = m.city ?? ""
        switch editingStatus {
        case .planned:
            start = m.plannedStart ?? start
            end = m.plannedEnd ?? end
        case .ongoing:
            start = m.startedAt ?? start
        case .finished:
            start = m.startedAt ?? start
            end = m.endedAt ?? end
        }
    }

    private func save() {
        let t = title.isEmpty ? nil : title
        let c = city.isEmpty ? nil : city
        switch mode {
        case .create(let couple):
            try? MeetingRepository(context: context).createPlanned(
                couple: couple, title: t, city: c, plannedStart: start, plannedEnd: end)
        case .edit(let m):
            try? MeetingRepository(context: context).update(
                m, title: t, city: c, start: start, end: showsEndDate ? end : nil)
        }
        dismiss()
    }
}
```

- [ ] **Step 2: 改调用点 `Features/Meetings/MeetingsView.swift`**

第 30 行 `if let couple = couples.first { MeetingFormView(couple: couple) }` 改为：

```swift
            if let couple = couples.first { MeetingFormView(mode: .create(couple)) }
```

- [ ] **Step 3: PlanView 加编辑入口与删除失效守卫（`Features/Plan/PlanView.swift`）**

3a. state 区（`@State private var showAdd = false` 之后）加两行：

```swift
    @State private var showEditForm = false
    @Environment(\.dismiss) private var dismiss
```

3b. 把现有 `var body: some View { ... }` 整体改名为 `private var content: some View { ... }`（内容不动），新增 body：

```swift
    var body: some View {
        // 删除后本页对象失效：立即退出，避免渲染已删 CDMeeting 触发 fault 崩溃
        if meeting.managedObjectContext == nil || meeting.isDeleted {
            Color.clear.onAppear { dismiss() }
        } else {
            content
        }
    }
```

3c. 在 content 的 `.safeAreaInset(edge: .bottom) { ... }` 之前加：

```swift
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") { showEditForm = true }
                    .font(.system(size: 14))
            }
        }
```

3d. 在 `.sheet(item: $editingItem) { ... }` 之后加：

```swift
        .sheet(isPresented: $showEditForm) { MeetingFormView(mode: .edit(meeting)) }
```

- [ ] **Step 4: MeetingDetailView 非计划态编辑入口（`Features/Meetings/MeetingDetailView.swift`）**

4a. view 顶部 state 区加 `@State private var showEditForm = false`。

4b. 现有 `.toolbar { if meeting.statusRaw == ... }` 块里、既有 ToolbarItem 之外，再加一个（planned 态由内嵌 PlanView 自带编辑，勿重复）：

```swift
            if meeting.statusRaw != MeetingStatus.planned.rawValue {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("编辑") { showEditForm = true }
                        .font(.system(size: 14))
                }
            }
```

4c. 在 `.confirmationDialog(...)` 之后加：

```swift
        .sheet(isPresented: $showEditForm) { MeetingFormView(mode: .edit(meeting)) }
```

- [ ] **Step 5: 构建 + 全量测试**

Run: `./scripts/gen.sh && ./scripts/build.sh && ./scripts/test.sh`
Expected: `✅ 构建通过` 且 `✅ 测试通过`

- [ ] **Step 6: Commit**

```bash
git add Features/Meetings/MeetingFormView.swift Features/Meetings/MeetingsView.swift Features/Plan/PlanView.swift Features/Meetings/MeetingDetailView.swift
git commit -m "见面表单双模式：三态可编辑，计划可删除，入口挂行前计划与详情页"
```

---

### Task 3: 心情卡标名字

**Files:**
- Modify: `Features/Home/HomeView.swift`（仅 `moodCard(_:)` 函数替换 + 新增 `moodSlot`）

**Interfaces:**
- Consumes: 既有 `CoupleRepository.currentPartner/otherPartner`、`DailyMoodRepository.mood(couple:authorID:day:calendar:)`、`ParchmentCard`、`DSPressEffect`、`DS.chipBorder/inkMuted`
- Produces: 无对外接口（纯视图内部）

- [ ] **Step 1: 替换 `HomeView.moodCard(_:)` 整个函数并新增辅助视图**

```swift
    private func moodCard(_ couple: CDCouple) -> some View {
        let repo = CoupleRepository(context: context)
        let me = repo.currentPartner(of: couple)
        let other = repo.otherPartner(of: couple)
        let moodRepo = DailyMoodRepository(context: context)
        let mine = moodRepo.mood(couple: couple, authorID: me?.id, day: Date(), calendar: .current)
        let partnerMood = other.flatMap {
            moodRepo.mood(couple: couple, authorID: $0.id, day: Date(), calendar: .current)
        }
        return Button {
            showMoodSheet = true
        } label: {
            ParchmentCard {
                HStack(alignment: .top, spacing: 14) {
                    Text("今日心情").dsCaption().padding(.top, 4)
                    moodSlot(name: me?.name ?? "我", emoji: mine?.moodEmoji)
                    moodSlot(name: other?.name ?? "TA", emoji: partnerMood?.moodEmoji)
                    Spacer()
                    if other != nil, partnerMood == nil {
                        Text("还没打卡").dsFootnote().padding(.top, 4)
                    }
                }
            }
        }
        .buttonStyle(DSPressEffect())
    }

    /// 心情槽位：emoji（或虚线空位）+ 正下方昵称小字，名字跟人走
    private func moodSlot(name: String, emoji: String?) -> some View {
        VStack(spacing: 3) {
            if let emoji {
                Text(emoji).font(.system(size: 18))
            } else {
                Circle().stroke(DS.chipBorder, style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .frame(width: 24, height: 24)
                    .overlay(Text("+").dsCaption())
            }
            Text(name).font(.system(size: 10)).foregroundStyle(DS.inkMuted)
        }
    }
```

- [ ] **Step 2: 构建 + 全量测试**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: `✅ 构建通过` 且 `✅ 测试通过`

- [ ] **Step 3: Commit**

```bash
git add Features/Home/HomeView.swift
git commit -m "心情卡：emoji 下标注昵称，空位虚线圈同样带名字"
```

---

### Task 4: SharingManager：配对状态纯函数 + 解除/退出薄层

**Files:**
- Modify: `Persistence/SharingManager.swift`
- Test: `Tests/SharingManagerTests.swift`（追加用例）

**Interfaces:**
- Consumes: 既有 `controller.container`（NSPersistentCloudKitContainer）、`controller.privateStore/sharedStore`、`persistUpdatedShare`、`loadShare(for:)`
- Produces（T5 依赖，签名照抄）:
  - `enum PairingStatus: Equatable { case notPaired, invited, connected }` + `var label: String`
  - `SharingManager.pairingStatus(shareExists:participantJoined:publicPermissionOpen:isParticipantDevice:) -> PairingStatus`（nonisolated static）
  - `func unpair(for couple: CDCouple) async`（创建方）
  - `func leaveSpace(for couple: CDCouple) async`（受邀方）

- [ ] **Step 1: 写失败测试**（`Tests/SharingManagerTests.swift` 追加）

```swift
    // spec §一 状态表：四态规则
    func testPairingStatusTable() {
        typealias S = SharingManager
        // 受邀方设备恒为已连接
        XCTAssertEqual(S.pairingStatus(shareExists: false, participantJoined: false,
                                       publicPermissionOpen: false, isParticipantDevice: true), .connected)
        // 无 share → 未配对
        XCTAssertEqual(S.pairingStatus(shareExists: false, participantJoined: false,
                                       publicPermissionOpen: true, isParticipantDevice: false), .notPaired)
        // 有参与者已接受 → 已连接（无论锁没锁）
        XCTAssertEqual(S.pairingStatus(shareExists: true, participantJoined: true,
                                       publicPermissionOpen: false, isParticipantDevice: false), .connected)
        // 无参与者 + 链接开着 → 邀请已发出
        XCTAssertEqual(S.pairingStatus(shareExists: true, participantJoined: false,
                                       publicPermissionOpen: true, isParticipantDevice: false), .invited)
        // 无参与者 + 已锁（解绑后遗留）→ 未配对
        XCTAssertEqual(S.pairingStatus(shareExists: true, participantJoined: false,
                                       publicPermissionOpen: false, isParticipantDevice: false), .notPaired)
    }

    func testPairingStatusLabels() {
        XCTAssertEqual(PairingStatus.notPaired.label, "未配对")
        XCTAssertEqual(PairingStatus.invited.label, "邀请已发出")
        XCTAssertEqual(PairingStatus.connected.label, "已连接")
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: 编译失败（`PairingStatus`/`pairingStatus` 未定义）

- [ ] **Step 3: 实现**（`Persistence/SharingManager.swift` 文件尾追加）

```swift
/// 设置页配对区的展示状态（spec §一 规则表）
enum PairingStatus: Equatable {
    case notPaired, invited, connected

    var label: String {
        switch self {
        case .notPaired: return "未配对"
        case .invited: return "邀请已发出"
        case .connected: return "已连接"
        }
    }
}

extension SharingManager {
    /// nonisolated 纯函数：只依赖入参，单测直调。
    /// 解绑后遗留的"已锁且无参与者" share 视同未配对——生成邀请走既有重开分支同链接复活。
    nonisolated static func pairingStatus(shareExists: Bool, participantJoined: Bool,
                                          publicPermissionOpen: Bool,
                                          isParticipantDevice: Bool) -> PairingStatus {
        if isParticipantDevice { return .connected }
        guard shareExists else { return .notPaired }
        if participantJoined { return .connected }
        return publicPermissionOpen ? .invited : .notPaired
    }

    /// 创建方解除配对：移除全部非 owner 参与者并锁链接，一次持久化。
    /// 失败时参与者移除无法本地回滚（CKShare 不支持重加），重拉云端真相代替回滚。
    func unpair(for couple: CDCouple) async {
        guard let share, let store = controller.privateStore else { return }
        share.participants.filter { $0.role != .owner }.forEach(share.removeParticipant)
        share.publicPermission = .none
        do {
            self.share = try await controller.container.persistUpdatedShare(share, in: store)
        } catch {
            lastError = "解除失败，请重试"
            await loadShare(for: couple)
        }
    }

    /// 受邀方解除配对：清除共享 zone（CloudKit 定义的"参与者退出共享"）。
    /// 成功后本机共享库清空 → RootView 的 couple FetchRequest 变空 → 自动回引导页。
    func leaveSpace(for couple: CDCouple) async {
        guard let sharedStore = controller.sharedStore,
              let zoneID = controller.container.recordID(for: couple.objectID)?.zoneID else {
            lastError = "解除失败，请重试"
            return
        }
        do {
            _ = try await controller.container.purgeObjectsAndRecordsInZone(with: zoneID, in: sharedStore)
        } catch {
            lastError = "解除失败，请重试"
        }
    }
}
```

注意：`lastError` 目前是 `private(set)`，本 extension 在同文件内可直接赋值，勿改访问级别。

- [ ] **Step 4: 跑测试确认通过**

Run: `./scripts/test.sh`
Expected: `✅ 测试通过`

- [ ] **Step 5: Commit**

```bash
git add Persistence/SharingManager.swift Tests/SharingManagerTests.swift
git commit -m "共享管理：配对四态规则表纯函数，创建方解除与受邀方退出薄层"
```

---

### Task 5: 设置页配对区按状态表重写 + 双侧解除入口

**Files:**
- Modify: `Features/Settings/SettingsView.swift`（配对与同步 section + 状态计算）

**Interfaces:**
- Consumes: T4 的 `PairingStatus`/`pairingStatus(...)`/`unpair(for:)`/`leaveSpace(for:)`；既有 `sharing.ensureShare/lockInvites/loadShare`、`GroupedRow`、`CoupleRepository.isParticipantDevice`
- Produces: 无对外接口。删除旧 `pairingStatusText`/`pairingStatusDone`

- [ ] **Step 1: 状态计算与弹窗文案（SettingsView 内加计算属性与 state）**

state 区加 `@State private var confirmUnpair = false`；类体内加：

```swift
    private var isParticipant: Bool {
        guard let couple = couples.first else { return false }
        return CoupleRepository(context: context).isParticipantDevice(couple)
    }

    private var pairingStatus: PairingStatus {
        SharingManager.pairingStatus(
            shareExists: sharing.share != nil,
            participantJoined: sharing.participantJoined,
            publicPermissionOpen: sharing.share?.publicPermission != CKShare.ParticipantPermission.none,
            isParticipantDevice: isParticipant)
    }

    /// 弹窗文案按角色（spec §一 文案照抄）
    private var unpairDialogMessage: String {
        isParticipant
            ? "解除后你的手机会清空这段空间并回到引导页；TA 那边的记录不受影响。想复合就让 TA 重新发邀请。"
            : "解除后 TA 的手机会清空这段空间并回到引导页；你的记录全部保留，重新发邀请可恢复。"
    }
```

注意 `!= CKShare.ParticipantPermission.none` 必须全限定写法——`!= .none` 会被解析成 Optional.none 恒真（P2 T8 踩过的坑）。

- [ ] **Step 2: 重写「配对与同步」GroupedSection**（整块替换为下文；旧的 `pairingStatusText`/`pairingStatusDone` 两个计算属性删除）

```swift
                Text("配对与同步").dsSectionTitle()
                GroupedSection {
                    GroupedRow(title: "配对状态", value: pairingStatus.label,
                               valueColor: pairingStatus == .connected ? DS.dsGreen : DS.inkMuted)
                    if let couple = couples.first, !isParticipant {
                        switch pairingStatus {
                        case .notPaired:
                            Button {
                                creatingShare = true
                                Task {
                                    defer { creatingShare = false }
                                    _ = try? await sharing.ensureShare(for: couple)
                                }
                            } label: {
                                GroupedRow(title: "还没配对", value: creatingShare ? "生成中…" : "生成邀请 ›",
                                           valueColor: DS.actionBlue)
                            }
                            .buttonStyle(.plain)
                            .disabled(creatingShare)
                        case .invited:
                            if let url = sharing.share?.url {
                                ShareLink(item: url) {
                                    GroupedRow(title: "邀请链接", value: "发出邀请 ›", valueColor: DS.actionBlue)
                                }
                                .buttonStyle(.plain)
                            }
                        case .connected:
                            if sharing.share?.publicPermission != CKShare.ParticipantPermission.none {
                                if let url = sharing.share?.url {
                                    ShareLink(item: url) {
                                        GroupedRow(title: "邀请链接", value: "发出邀请 ›", valueColor: DS.actionBlue)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button {
                                    Task { await sharing.lockInvites() }
                                } label: {
                                    GroupedRow(title: "对方已加入", value: "锁定邀请 ›", valueColor: DS.actionBlue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    GroupedRow(title: "iCloud 账号", value: accountAvailable ? "正常" : "未登录",
                               valueColor: accountAvailable ? DS.dsGreen : DS.dsRed,
                               showsDivider: pairingStatus == .connected)
                    if pairingStatus == .connected {
                        Button { confirmUnpair = true } label: {
                            HStack {
                                Text("解除配对").dsBody().foregroundStyle(DS.dsRed)
                                Spacer()
                                Text("›").dsBody().foregroundStyle(DS.dsRed)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 11)
                        }
                        .buttonStyle(DSPressEffect())
                    }
                    if let error = sharing.lastError {
                        Text(error).font(.system(size: 12)).foregroundStyle(DS.dsRed)
                            .padding(.horizontal, 14).padding(.bottom, 8)
                    }
                }
                if pairingStatus == .connected {
                    Text(isParticipant
                         ? "解除配对后你的手机会清空这段空间；TA 的记录不受影响。"
                         : "解除配对后 TA 的手机会清空这段空间；你的记录全部保留。")
                        .dsFootnote().padding(.horizontal, 4)
                }
```

- [ ] **Step 3: 挂确认弹窗**（`.onDisappear(perform: save)` 之前加）

```swift
        .confirmationDialog("解除配对？", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("解除配对", role: .destructive) {
                guard let couple = couples.first else { return }
                let participant = isParticipant
                Task {
                    if participant {
                        await sharing.leaveSpace(for: couple)
                    } else {
                        await sharing.unpair(for: couple)
                    }
                }
            }
        } message: {
            Text(unpairDialogMessage)
        }
```

- [ ] **Step 4: 构建 + 全量测试**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: `✅ 构建通过` 且 `✅ 测试通过`

- [ ] **Step 5: Commit**

```bash
git add Features/Settings/SettingsView.swift
git commit -m "设置页：配对区四态化，双侧红色解除配对入口与角色化确认文案"
```

---

### Task 6: 受邀方加入确认页 + RootView 门

**Files:**
- Create: `Features/Onboarding/JoinNameConfirmView.swift`
- Modify: `App/RootView.swift`
- Test: `Tests/JoinNameConfirmTests.swift`（新建）

**Interfaces:**
- Consumes: 既有 `CoupleRepository.isParticipantDevice/currentPartner`、`BluePillButtonStyle(fullWidth:)`、`GroupedSection`、DS tokens
- Produces: `enum JoinNameConfirm { static func isNeeded(isParticipantDevice: Bool, coupleID: UUID?, confirmedCoupleID: String) -> Bool }`；`JoinNameConfirmView(couple:)`；`@AppStorage("nameConfirmedCoupleID")`（存已确认 couple 的 UUID 字符串——单键存值，RootView 可观察；spec 里"按 couple 键控旗标"以此等价实现）

- [ ] **Step 1: 写失败测试**（新建 `Tests/JoinNameConfirmTests.swift`，全文如下）

```swift
import XCTest
@testable import Anniversary

final class JoinNameConfirmTests: XCTestCase {
    func testCreatorDeviceNeverNeedsConfirm() {
        XCTAssertFalse(JoinNameConfirm.isNeeded(isParticipantDevice: false,
                                                coupleID: UUID(), confirmedCoupleID: ""))
    }

    func testParticipantNeedsConfirmForNewCouple() {
        XCTAssertTrue(JoinNameConfirm.isNeeded(isParticipantDevice: true,
                                               coupleID: UUID(), confirmedCoupleID: ""))
    }

    func testParticipantSkipsWhenAlreadyConfirmed() {
        let id = UUID()
        XCTAssertFalse(JoinNameConfirm.isNeeded(isParticipantDevice: true,
                                                coupleID: id, confirmedCoupleID: id.uuidString))
    }

    func testNilCoupleIDNeverNeedsConfirm() {
        // id 缺失时若返回 true 会因确认动作写不进有效 id 而死循环卡在确认页
        XCTAssertFalse(JoinNameConfirm.isNeeded(isParticipantDevice: true,
                                                coupleID: nil, confirmedCoupleID: ""))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/gen.sh && ./scripts/test.sh`
Expected: 编译失败（`JoinNameConfirm` 未定义）

- [ ] **Step 3: 实现**（新建 `Features/Onboarding/JoinNameConfirmView.swift`，全文如下）

```swift
import SwiftUI

/// 加入确认页的出场判定。单测直调；nil id 必须返回 false（否则确认动作写不进有效 id，页面死循环）。
enum JoinNameConfirm {
    static func isNeeded(isParticipantDevice: Bool, coupleID: UUID?, confirmedCoupleID: String) -> Bool {
        guard isParticipantDevice, let id = coupleID else { return false }
        return id.uuidString != confirmedCoupleID
    }
}

/// 受邀方一次性确认页：TA 取的昵称在这里改成自己的（spec §二）。
/// 确认写入即置位 @AppStorage → RootView 观察到变化自动切主界面。
struct JoinNameConfirmView: View {
    @Environment(\.managedObjectContext) private var context
    let couple: CDCouple
    @AppStorage("nameConfirmedCoupleID") private var confirmedCoupleID = ""
    @State private var name = ""
    @State private var loaded = false

    private var canConfirm: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                RoundedRectangle(cornerRadius: DS.Radius.large)
                    .fill(DS.parchment)
                    .frame(height: 180)
                    .overlay(
                        Image(systemName: "party.popper.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(DS.actionBlue)
                    )

                VStack(spacing: 6) {
                    Text("欢迎加入我们的空间").dsHero()
                    Text("TA 给你取的昵称是「\(givenName)」。\n喜欢就直接确认，想改就改成你自己的。")
                        .dsCaption()
                        .multilineTextAlignment(.center)
                }

                GroupedSection {
                    HStack {
                        Text("我的昵称").dsBody()
                        TextField("", text: $name).multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                }

                Button("就用这个昵称") { confirm() }
                    .buttonStyle(BluePillButtonStyle(fullWidth: true))
                    .disabled(!canConfirm)
                    .opacity(canConfirm ? 1 : 0.4)

                Text("以后只有你自己能改它").dsFootnote()
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = givenName
        }
    }

    private var givenName: String {
        CoupleRepository(context: context).currentPartner(of: couple)?.name ?? ""
    }

    private func confirm() {
        let repo = CoupleRepository(context: context)
        repo.currentPartner(of: couple)?.name = name.trimmingCharacters(in: .whitespaces)
        try? context.save()
        confirmedCoupleID = couple.id?.uuidString ?? ""
    }
}
```

- [ ] **Step 4: RootView 插分支（`App/RootView.swift` 全文替换）**

```swift
import SwiftUI

struct RootView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @AppStorage("nameConfirmedCoupleID") private var confirmedCoupleID = ""

    var body: some View {
        if let couple = couples.first {
            if JoinNameConfirm.isNeeded(
                isParticipantDevice: CoupleRepository(context: context).isParticipantDevice(couple),
                coupleID: couple.id,
                confirmedCoupleID: confirmedCoupleID) {
                JoinNameConfirmView(couple: couple)
            } else {
                MainShell()
            }
        } else {
            OnboardingView()
        }
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PreviewData.makeController().viewContext)
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `./scripts/test.sh`
Expected: `✅ 测试通过`

- [ ] **Step 6: Commit**

```bash
git add Features/Onboarding/JoinNameConfirmView.swift App/RootView.swift Tests/JoinNameConfirmTests.swift
git commit -m "加入确认页：受邀方进主界面前自定昵称，RootView 按确认旗标分流"
```

---

### Task 7: 昵称锁定规则（TA 的昵称已连接后只读）

**Files:**
- Modify: `Persistence/CoupleRepository.swift`（加 static 纯函数）
- Modify: `Features/Settings/SettingsView.swift`（TA 昵称行 + save 限制）
- Test: `Tests/CoupleRepositoryTests.swift`（追加用例）

**Interfaces:**
- Consumes: T4/T5 已就位的 `sharing.participantJoined`、`isParticipant`（SettingsView 计算属性）
- Produces: `CoupleRepository.canEditPartnerName(isParticipantDevice:participantJoined:) -> Bool`（static）

- [ ] **Step 1: 写失败测试**（`Tests/CoupleRepositoryTests.swift` 追加）

```swift
    // spec §二：已连接后 TA 的昵称只能 TA 自己改；未配对时创建方可改（改错别字）
    func testCanEditPartnerNameRules() {
        XCTAssertTrue(CoupleRepository.canEditPartnerName(isParticipantDevice: false, participantJoined: false))
        XCTAssertFalse(CoupleRepository.canEditPartnerName(isParticipantDevice: false, participantJoined: true))
        XCTAssertFalse(CoupleRepository.canEditPartnerName(isParticipantDevice: true, participantJoined: false))
        XCTAssertFalse(CoupleRepository.canEditPartnerName(isParticipantDevice: true, participantJoined: true))
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: 编译失败（`canEditPartnerName` 未定义）

- [ ] **Step 3: 实现纯函数**（`Persistence/CoupleRepository.swift` struct 内追加）

```swift
    /// 已连接后 TA 的昵称只能 TA 自己改：受邀方永不可改对方；创建方在对方加入后不可改。
    /// 未配对/邀请未被接受时创建方可改两个名字（TA 本人还没进来，得能改错别字）。
    static func canEditPartnerName(isParticipantDevice: Bool, participantJoined: Bool) -> Bool {
        !isParticipantDevice && !participantJoined
    }
```

- [ ] **Step 4: SettingsView 接线**

4a. 计算属性区（T5 加的 `isParticipant` 之后）加：

```swift
    private var canEditPartnerNameNow: Bool {
        CoupleRepository.canEditPartnerName(isParticipantDevice: isParticipant,
                                            participantJoined: sharing.participantJoined)
    }
```

4b. 「我们的资料」里 TA 的昵称行整块替换：

```swift
                    HStack {
                        Text("TA 的昵称").dsBody()
                        if canEditPartnerNameNow {
                            TextField("", text: $partnerName).multilineTextAlignment(.trailing)
                                .onSubmit(save)
                        } else {
                            Spacer()
                            Text(partnerName).dsBody().foregroundStyle(DS.inkMuted)
                            Image(systemName: "lock")
                                .font(.system(size: 11))
                                .foregroundStyle(DS.chipBorder)
                        }
                    }
```

4c. 资料 GroupedSection 闭合后加脚注：

```swift
                if !canEditPartnerNameNow {
                    Text("TA 的昵称由 TA 自己定").dsFootnote().padding(.horizontal, 4)
                }
```

4d. `save()` 里 partnerName 分支加权限守卫：

```swift
        if !partnerName.trimmingCharacters(in: .whitespaces).isEmpty, canEditPartnerNameNow {
            repo.otherPartner(of: couple)?.name = partnerName
        }
```

已知小时差（接受，不修）：`sharing.loadShare` 异步返回前 `participantJoined` 为 false，创建方端锁行可能闪现可编辑态几百毫秒；save 同门禁保护，无实害。

- [ ] **Step 5: 跑测试确认通过**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: `✅ 构建通过` 且 `✅ 测试通过`

- [ ] **Step 6: Commit**

```bash
git add Persistence/CoupleRepository.swift Features/Settings/SettingsView.swift Tests/CoupleRepositoryTests.swift
git commit -m "昵称严格各改各的：已连接后 TA 昵称只读，save 同门禁"
```

---

### Task 8: 版本 0.2.1 / 构建号 4 + 验收清单补三条

**Files:**
- Modify: `project.yml`（两个数字）
- Modify: `docs/RELEASE.md`（§7 追加 13–15）

**Interfaces:**
- Consumes: 无
- Produces: 无（发布配置与文档）

- [ ] **Step 1: `project.yml` 版本号**

`MARKETING_VERSION: 0.2.0` → `MARKETING_VERSION: 0.2.1`；`CURRENT_PROJECT_VERSION: 3` → `CURRENT_PROJECT_VERSION: 4`。

- [ ] **Step 2: `docs/RELEASE.md` §7 清单尾追加**

```markdown
13. 解除配对（创建方发起）：你端设置点「解除配对」→ 确认 → 状态变未配对；她端 App 放前台等一会儿自动清空回引导页。你端再点「生成邀请」（同链接复活）→ 她重走加入 → 恢复如初。
14. 解除配对（受邀方发起）：反向同验——她端点「解除配对」→ 本机清空回引导页；你端「配对状态」恢复未配对、可重新邀请。
15. 加入确认页：她接受邀请后先见「欢迎加入我们的空间」，确认/修改昵称后进主界面；改名几秒内你端可见；你端设置里她的昵称行变只读带锁。
```

- [ ] **Step 3: 重新生成 + 构建 + 全量测试**

Run: `./scripts/gen.sh && ./scripts/build.sh && ./scripts/test.sh`
Expected: `✅ 构建通过` 且 `✅ 测试通过`

- [ ] **Step 4: Commit**

```bash
git add project.yml docs/RELEASE.md
git commit -m "版本 0.2.1 构建号 4，验收清单补解绑与加入确认三条"
```

---

## 设备复测清单（合并归档后，随 TestFlight 0.2.1 双机跑）

1. 计划中的见面：行前计划页右上「编辑」→ 改标题/城市/日期生效；「删除这次计划」→ 弹窗确认 → 页面自动退出，足迹列表消失，后续见面序号前移。
2. 进行中的见面：详情页「编辑」只见「实际开始」无结束行；无删除按钮。
3. 已结束的见面：详情页「编辑」可改实际起止；无删除按钮。
4. 心情卡：两人各打卡后，emoji 下各自名字；单侧未打卡显示虚线圈+名字+「还没打卡」。
5. RELEASE.md §7 第 13–15 条（解绑双向 + 复合 + 加入确认页）。
6. 已连接后两端设置页：TA 的昵称行只读带锁、脚注在；改自己昵称对端几秒可见。
7. 解绑她端后她的旧「确认页旗标」仍存：她若重新加入同一空间不再弹确认页（预期行为，名字已是她定的）。
8. 升级安装 0.2.1 后她端首启会补弹一次确认页（旗标为空，预填现名，点一下即过）——提前告知她这是预期。

## 执行备注（SDD 派单）

- 实现者模型：T1/T4 sonnet（逻辑+测试）；T2/T5/T6 sonnet（多文件 UI 接线）；T3/T7/T8 haiku（转写型小改）。审查者一律 sonnet；终局全分支审查 fable。
- T2 依赖 T1；T5 依赖 T4；T7 依赖 T5 的 `isParticipant` 属性（若并行派单，T7 必须晚于 T5 合入）。T3 独立可穿插。
- CloudKit 真机行为（unpair/leaveSpace 的网络路径、purge 后 RootView 回退）不进单测，全靠设备复测清单第 5 条。
