# P1 记忆核心 实现计划（计划 2/7）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 P0 地基上交付单机可用的记忆核心：见面/约会日/记忆/行前计划/每日心情的完整数据层与状态机，加上 Tab 壳、⊕ 动作面板、引导页、首页、见面列表/详情时间线、行前计划页、新建记忆表单、设置最小集——P1 合并后用户即可在自己手机上真实使用。

**Architecture:** 数据层延续 P0 仓库模式（struct + NSManagedObjectContext，业务规则纯函数化并单测锁死）；封盘状态机落在 MeetingRepository（约会日惰性创建：首条记录开第 1 天，封盘后下一条自动开新天，18 小时补封拦截）。UI 层新增 Features/ 目录按功能分文件夹，App/ 仅保留壳与路由；所有界面复用 P0 设计系统组件，遵循已批准的 Apple 摄影优先风小样。

**Tech Stack:** Swift 5.10 / SwiftUI / Core Data / PhotosUI (PhotosPicker) / CoreLocation + CLGeocoder / ImageIO（缩略图降采样）/ XCTest

**范围说明:** 设计文档 §11 的 P1 阶段。P1 不含：云同步与配对（P2）、日历双投影/地图/地点归并建议/路线图（P3）、互评喜怒（P4）、经期亲密（P5）、Face ID 锁与动画打磨（P6）。⊕ 面板中未到阶段的入口以禁用态展示。

## Global Constraints

- 部署目标 iOS 18.0；仅 iPhone；竖屏；只用 iOS 18 可用 API（禁 iOS 26 独占）。
- 零第三方运行时依赖；构建/测试只用 `./scripts/gen.sh`、`./scripts/test.sh`；新增源文件后必须先 gen 再 test。
- **保序硬约束（P0 终局审查裁定）**：`partners(of:)[0]` 必须始终是创建者。本计划 Task 1 以 `roleIndex`（创建者=0，对方=1）落实，此后任何排序改动都不得破坏该契约。
- **禁写 `CDPlace.categoryRaw`**（P3 前必须先定 PlaceCategory 枚举 + raw 锁死测试）；P1 创建的 CDPlace 只写 id/name/address/latitude/longitude/createdAt/couple。
- CloudKit 建模约束延续（新增属性必须 optional 或带 defaultValue；关系 optional；不用 unique/ordered）。
- 照片：原图 Data 原样入库（不压缩不转码），缩略图长边 600px JPEG 0.7 由 Thumbnailer 生成存 thumbnailData。
- 约会日规则按 spec §5.1 逐字执行：纯手动封盘；无开着的约会日时新记录自动开启下一天（首条即第 1 天）；距开日超 18 小时未封盘且要新建记录 → 补封拦截（补封时刻可手选）；见面结束时一并封盘。
- 计划条目排序规则（spec §6）：日期→时间→sortIndex；无日期归备忘区；同日内无时间（全天）排在有时间之前。
- 视觉令牌/组件全部复用 P0 `DS`/`DSTypography`/`DSButtons`/`DSCards`/`DSChips`；深色内容一律圆角卡片禁止通栏；全系统唯一投影只给照片。
- 按钮文案单行 ≤6 字、不含 emoji；emoji 只作为内容（心情、评价表情）。全部 UI 文案简体中文。
- 逻辑任务（Task 1–6）严格 TDD；UI 任务（Task 7–15）以构建通过为门 + Preview；提交信息中文动词开头。

## 文件结构总览

```
App/
├── AnniversaryApp.swift      （已有，不动）
├── RootView.swift            （T8 改：onboarding ⇄ MainShell 路由）
├── MainShell.swift           （T7 新：四 Tab + ⊕ 底栏壳）
└── ActionPanel.swift         （T7 新：⊕ 底部动作面板）
Features/
├── Onboarding/OnboardingView.swift            （T8）
├── Home/HomeView.swift · MoodSheet.swift      （T9）
├── Meetings/MeetingsView.swift · MeetingFormView.swift        （T10）
├── Meetings/MeetingDetailView.swift · TimelineListView.swift · SealSheet.swift （T13）
├── Plan/PlanView.swift · PlanItemFormSheet.swift              （T11）
├── Moments/MomentFormView.swift · StaleSealSheet.swift        （T12）
├── Moments/MomentDetailView.swift · PhotoViewerView.swift     （T14）
└── Settings/SettingsView.swift                                （T15）
Persistence/
├── CoupleRepository.swift    （T1 改：roleIndex）
├── MeetingRepository.swift   （T2 新 + T3 扩：封盘状态机）
├── MomentRepository.swift    （T4 新）
├── PlanItemRepository.swift  （T5 新）
└── DailyMoodRepository.swift （T6 新）
Support/
├── Thumbnailer.swift         （T4 新）
├── HomeLogic.swift           （T6 新）
├── Formatters.swift          （T7 新）
├── LocationFetcher.swift     （T12 新）
└── PreviewData.swift         （T16 扩）
Domain/
├── ModelSchema.swift         （T1 改：partner.roleIndex 属性）
└── ManagedObjects.swift      （T1 改：CDPartner.roleIndex）
project.yml                   （T7 改：sources 加 Features；T12 改：定位权限文案）
```

---

### Task 1: roleIndex 保序迁移

**Files:**
- Modify: `Domain/ModelSchema.swift`（partner 实体属性列表）
- Modify: `Domain/ManagedObjects.swift`（CDPartner）
- Modify: `Persistence/CoupleRepository.swift`
- Test: `Tests/CoupleRepositoryTests.swift`（追加）、`Tests/ModelSchemaTests.swift`（追加）

**Interfaces:**
- Consumes: P0 的 `CoupleRepository.bootstrapIfNeeded/partners(of:)`
- Produces: `CDPartner.roleIndex: Int16`（0=创建者/我，1=对方）；`partners(of:)` 按 roleIndex 升序；新增便捷方法 `creatorID(of couple: CDCouple) -> UUID?`。后续所有任务用 `creatorID` 作为 authorID。

- [ ] **Step 1: 写失败测试**

在 `Tests/ModelSchemaTests.swift` 类内追加：

```swift
    func testPartnerHasRoleIndexWithDefault() {
        let partner = model.entitiesByName["CDPartner"]!
        let attr = partner.attributesByName["roleIndex"]
        XCTAssertNotNil(attr)
        XCTAssertFalse(attr!.isOptional)
        XCTAssertEqual(attr!.defaultValue as? Int16, 0)
    }
```

在 `Tests/CoupleRepositoryTests.swift` 类内追加：

```swift
    func testPartnersOrderedByRoleIndexAndCreatorID() throws {
        let pc = PersistenceController(inMemory: true)
        let repo = CoupleRepository(context: pc.viewContext)
        let couple = try repo.bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)

        let partners = repo.partners(of: couple)
        XCTAssertEqual(partners.map(\.roleIndex), [0, 1])
        XCTAssertEqual(partners.map(\.name), ["阿铖", "小于"])
        XCTAssertNil(partners[0].themeColorHex)
        XCTAssertEqual(repo.creatorID(of: couple), partners[0].id)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL（roleIndex 不存在 → 编译错误即视为失败）

- [ ] **Step 3: 修改模型与托管对象**

`Domain/ModelSchema.swift`：在 partner 实体的属性数组中（`attr("tracksCycle", ...)` 之后）追加一行：

```swift
            attr("roleIndex", .integer16AttributeType, optional: false, defaultValue: 0),
```

`Domain/ManagedObjects.swift`：在 `CDPartner` 中 `tracksCycle` 之后追加：

```swift
    @NSManaged var roleIndex: Int16
```

- [ ] **Step 4: 改写 CoupleRepository**

`Persistence/CoupleRepository.swift` 全文替换：

```swift
import CoreData

struct CoupleRepository {
    let context: NSManagedObjectContext

    func fetchCouple() throws -> CDCouple? {
        let request = CDCouple.fetchRequest()
        request.fetchLimit = 1
        return try context.fetch(request).first as? CDCouple
    }

    @discardableResult
    func bootstrapIfNeeded(myName: String, partnerName: String, anniversary: Date?) throws -> CDCouple {
        if let existing = try fetchCouple() { return existing }

        let now = Date()
        let couple = CDCouple(context: context)
        couple.id = UUID()
        couple.createdAt = now
        couple.anniversaryDate = anniversary

        let me = CDPartner(context: context)
        me.id = UUID()
        me.name = myName
        me.roleIndex = 0
        me.couple = couple

        let partner = CDPartner(context: context)
        partner.id = UUID()
        partner.name = partnerName
        partner.roleIndex = 1
        partner.couple = couple

        try context.save()
        return couple
    }

    /// [0]=创建者/我（roleIndex 0），[1]=对方（roleIndex 1）。保序硬约束，禁止更改排序键。
    func partners(of couple: CDCouple) -> [CDPartner] {
        let set = (couple.partners as? Set<CDPartner>) ?? []
        return set.sorted { $0.roleIndex < $1.roleIndex }
    }

    /// 创建者（单机阶段即"我"）的业务 ID，用作各类记录的 authorID
    func creatorID(of couple: CDCouple) -> UUID? {
        partners(of: couple).first?.id
    }
}
```

（P0 借用 themeColorHex 排序的写法就此移除；仓库从未发布真实数据，无需运行时数据迁移。roleIndex 为带默认值的追加属性，CloudKit 兼容。）

- [ ] **Step 5: 跑测试确认通过**

Run: `./scripts/gen.sh && ./scripts/test.sh`
Expected: PASS（含 P0 既有全部用例——`testBootstrapCreatesCoupleWithTwoPartners` 等应继续通过）

- [ ] **Step 6: Commit**

```bash
git add Domain Persistence/CoupleRepository.swift Tests
git commit -m "迁移伙伴排序到 roleIndex 并新增创建者 ID 便捷方法"
```

---

### Task 2: MeetingRepository 生命周期

**Files:**
- Create: `Persistence/MeetingRepository.swift`
- Test: `Tests/MeetingRepositoryTests.swift`

**Interfaces:**
- Consumes: `CDCouple/CDMeeting`、`MeetingStatus`
- Produces: `MeetingRepository(context:)`：`createPlanned(couple:title:city:plannedStart:plannedEnd:) -> CDMeeting`（index 自增）、`start(_:at:)`、`end(_:at:)`（T3 会扩展封盘行为）、`ongoingMeeting(couple:) -> CDMeeting?`、`nextPlannedMeeting(couple:after:) -> CDMeeting?`、`meetingsSorted(couple:) -> [CDMeeting]`（index 降序）、`status(of:) -> MeetingStatus`

- [ ] **Step 1: 写失败测试**

`Tests/MeetingRepositoryTests.swift`:

```swift
import XCTest
@testable import Anniversary

final class MeetingRepositoryTests: XCTestCase {
    private func makeCouple() throws -> (PersistenceController, CDCouple) {
        let pc = PersistenceController(inMemory: true)
        let couple = try CoupleRepository(context: pc.viewContext)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        return (pc, couple)
    }

    func testCreatePlannedAutoIncrementsIndex() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)

        let m1 = try repo.createPlanned(couple: couple, title: nil, city: "上海",
                                        plannedStart: Date(timeIntervalSince1970: 100), plannedEnd: nil)
        let m2 = try repo.createPlanned(couple: couple, title: "秋游", city: "杭州",
                                        plannedStart: Date(timeIntervalSince1970: 200), plannedEnd: nil)

        XCTAssertEqual(m1.index, 1)
        XCTAssertEqual(m2.index, 2)
        XCTAssertEqual(repo.status(of: m1), .planned)
    }

    func testStartAndEndTransitions() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)

        let t1 = Date(timeIntervalSince1970: 1_000)
        try repo.start(m, at: t1)
        XCTAssertEqual(repo.status(of: m), .ongoing)
        XCTAssertEqual(m.startedAt, t1)
        XCTAssertEqual(try repo.ongoingMeeting(couple: couple)?.objectID, m.objectID)

        let t2 = Date(timeIntervalSince1970: 2_000)
        try repo.end(m, at: t2)
        XCTAssertEqual(repo.status(of: m), .finished)
        XCTAssertEqual(m.endedAt, t2)
        XCTAssertNil(try repo.ongoingMeeting(couple: couple))
    }

    func testNextPlannedPicksEarliestUpcoming() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        let now = Date(timeIntervalSince1970: 10_000)

        _ = try repo.createPlanned(couple: couple, title: "过去的", city: nil,
                                   plannedStart: now.addingTimeInterval(-86_400), plannedEnd: nil)
        let near = try repo.createPlanned(couple: couple, title: "近", city: nil,
                                          plannedStart: now.addingTimeInterval(86_400), plannedEnd: nil)
        _ = try repo.createPlanned(couple: couple, title: "远", city: nil,
                                   plannedStart: now.addingTimeInterval(10 * 86_400), plannedEnd: nil)

        XCTAssertEqual(try repo.nextPlannedMeeting(couple: couple, after: now)?.objectID, near.objectID)
    }

    func testMeetingsSortedNewestFirst() throws {
        let (pc, couple) = try makeCouple()
        let repo = MeetingRepository(context: pc.viewContext)
        _ = try repo.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)
        _ = try repo.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil, plannedEnd: nil)

        XCTAssertEqual(try repo.meetingsSorted(couple: couple).map(\.index), [2, 1])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL（MeetingRepository 未定义）

- [ ] **Step 3: 实现**

`Persistence/MeetingRepository.swift`:

```swift
import CoreData

struct MeetingRepository {
    let context: NSManagedObjectContext

    func status(of meeting: CDMeeting) -> MeetingStatus {
        MeetingStatus(rawValue: meeting.statusRaw) ?? .planned
    }

    @discardableResult
    func createPlanned(couple: CDCouple, title: String?, city: String?,
                       plannedStart: Date?, plannedEnd: Date?) throws -> CDMeeting {
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
        meeting.couple = couple
        try context.save()
        return meeting
    }

    func start(_ meeting: CDMeeting, at date: Date) throws {
        meeting.statusRaw = MeetingStatus.ongoing.rawValue
        meeting.startedAt = date
        try context.save()
    }

    func end(_ meeting: CDMeeting, at date: Date) throws {
        try sealOpenDay(in: meeting, at: date)
        meeting.statusRaw = MeetingStatus.finished.rawValue
        meeting.endedAt = date
        try context.save()
    }

    func ongoingMeeting(couple: CDCouple) throws -> CDMeeting? {
        ((couple.meetings as? Set<CDMeeting>) ?? [])
            .first { $0.statusRaw == MeetingStatus.ongoing.rawValue }
    }

    func nextPlannedMeeting(couple: CDCouple, after date: Date) throws -> CDMeeting? {
        ((couple.meetings as? Set<CDMeeting>) ?? [])
            .filter { $0.statusRaw == MeetingStatus.planned.rawValue }
            .filter { ($0.plannedStart ?? .distantFuture) >= date }
            .min { ($0.plannedStart ?? .distantFuture) < ($1.plannedStart ?? .distantFuture) }
    }

    func meetingsSorted(couple: CDCouple) throws -> [CDMeeting] {
        ((couple.meetings as? Set<CDMeeting>) ?? [])
            .sorted { $0.index > $1.index }
    }
}
```

注意：`end` 已调用 `sealOpenDay`——该方法在本任务先以最小实现出现（见下），T3 为其补全状态机与测试：

在同文件底部追加：

```swift
extension MeetingRepository {
    /// 封掉当前开着的约会日（无开着的天则为 no-op）。完整状态机见约会日扩展。
    func sealOpenDay(in meeting: CDMeeting, at date: Date) throws {
        guard let day = try openDay(in: meeting) else { return }
        day.closedAt = date
        try context.save()
    }

    /// 当前开着的约会日：closedAt == nil 中 dayIndex 最大者
    func openDay(in meeting: CDMeeting) throws -> CDDateDay? {
        ((meeting.dateDays as? Set<CDDateDay>) ?? [])
            .filter { $0.closedAt == nil }
            .max { $0.dayIndex < $1.dayIndex }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `./scripts/gen.sh && ./scripts/test.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Persistence/MeetingRepository.swift Tests/MeetingRepositoryTests.swift
git commit -m "添加见面仓库生命周期（计划/开始/结束与查询）"
```

---

### Task 3: 约会日封盘状态机

**Files:**
- Modify: `Persistence/MeetingRepository.swift`（扩展 extension）
- Test: `Tests/DateDayMachineTests.swift`

**Interfaces:**
- Consumes: T2 的 MeetingRepository
- Produces: `dayForNewRecord(in:at:) -> CDDateDay`（开着的天或新开 dayIndex=max+1）、`staleOpenDay(in:now:threshold:) -> CDDateDay?`（默认阈值 64800 秒 = 18h）、`daysSorted(in:) -> [CDDateDay]`（dayIndex 升序）。`sealOpenDay/openDay` 语义不变。

- [ ] **Step 1: 写失败测试**

`Tests/DateDayMachineTests.swift`:

```swift
import XCTest
@testable import Anniversary

final class DateDayMachineTests: XCTestCase {
    private func makeOngoingMeeting() throws -> (PersistenceController, MeetingRepository, CDMeeting) {
        let pc = PersistenceController(inMemory: true)
        let couple = try CoupleRepository(context: pc.viewContext)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        let repo = MeetingRepository(context: pc.viewContext)
        let m = try repo.createPlanned(couple: couple, title: nil, city: "上海", plannedStart: nil, plannedEnd: nil)
        try repo.start(m, at: Date(timeIntervalSince1970: 0))
        return (pc, repo, m)
    }

    func testFirstRecordOpensDayOne() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        let t = Date(timeIntervalSince1970: 1_000)

        let day = try repo.dayForNewRecord(in: m, at: t)

        XCTAssertEqual(day.dayIndex, 1)
        XCTAssertEqual(day.openedAt, t)
        XCTAssertNil(day.closedAt)
    }

    func testSecondRecordReusesOpenDay() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        let d1 = try repo.dayForNewRecord(in: m, at: Date(timeIntervalSince1970: 1_000))
        let d2 = try repo.dayForNewRecord(in: m, at: Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(d1.objectID, d2.objectID)
        XCTAssertEqual(try repo.daysSorted(in: m).count, 1)
    }

    func testSealThenNewRecordOpensNextDay() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        _ = try repo.dayForNewRecord(in: m, at: Date(timeIntervalSince1970: 1_000))
        try repo.sealOpenDay(in: m, at: Date(timeIntervalSince1970: 40_000))

        let day2 = try repo.dayForNewRecord(in: m, at: Date(timeIntervalSince1970: 50_000))

        XCTAssertEqual(day2.dayIndex, 2)
        let days = try repo.daysSorted(in: m)
        XCTAssertEqual(days.map(\.dayIndex), [1, 2])
        XCTAssertNotNil(days[0].closedAt)
        XCTAssertNil(days[1].closedAt)
    }

    func testStaleOpenDayAt18HourBoundary() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        let opened = Date(timeIntervalSince1970: 0)
        _ = try repo.dayForNewRecord(in: m, at: opened)

        let justUnder = opened.addingTimeInterval(18 * 3600 - 60)
        let justOver = opened.addingTimeInterval(18 * 3600 + 60)

        XCTAssertNil(try repo.staleOpenDay(in: m, now: justUnder))
        XCTAssertNotNil(try repo.staleOpenDay(in: m, now: justOver))
    }

    func testEndMeetingSealsOpenDay() throws {
        let (_, repo, m) = try makeOngoingMeeting()
        _ = try repo.dayForNewRecord(in: m, at: Date(timeIntervalSince1970: 1_000))

        let endTime = Date(timeIntervalSince1970: 90_000)
        try repo.end(m, at: endTime)

        XCTAssertNil(try repo.openDay(in: m))
        XCTAssertEqual(try repo.daysSorted(in: m).first?.closedAt, endTime)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL（dayForNewRecord/staleOpenDay/daysSorted 未定义）

- [ ] **Step 3: 实现（追加到 MeetingRepository.swift 的 extension 内）**

在 T2 建的 `extension MeetingRepository` 中追加三个方法：

```swift
    /// 新记录归属的约会日：有开着的天用之；否则新开 dayIndex = 已有最大值 + 1（首条即第 1 天）
    @discardableResult
    func dayForNewRecord(in meeting: CDMeeting, at date: Date) throws -> CDDateDay {
        if let open = try openDay(in: meeting) { return open }
        let maxIndex = ((meeting.dateDays as? Set<CDDateDay>) ?? [])
            .map(\.dayIndex).max() ?? 0
        let day = CDDateDay(context: context)
        day.id = UUID()
        day.dayIndex = maxIndex + 1
        day.openedAt = date
        day.meeting = meeting
        try context.save()
        return day
    }

    /// 开着的约会日已超过阈值（默认 18 小时）未封盘 → 返回该天（用于新建记录前的补封拦截）
    func staleOpenDay(in meeting: CDMeeting, now: Date,
                      threshold: TimeInterval = 18 * 3600) throws -> CDDateDay? {
        guard let open = try openDay(in: meeting),
              let openedAt = open.openedAt,
              now.timeIntervalSince(openedAt) > threshold else { return nil }
        return open
    }

    func daysSorted(in meeting: CDMeeting) throws -> [CDDateDay] {
        ((meeting.dateDays as? Set<CDDateDay>) ?? [])
            .sorted { $0.dayIndex < $1.dayIndex }
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `./scripts/gen.sh && ./scripts/test.sh`
Expected: PASS（含 T2 全部用例）

- [ ] **Step 5: Commit**

```bash
git add Persistence/MeetingRepository.swift Tests/DateDayMachineTests.swift
git commit -m "实现约会日封盘状态机（惰性开日/顺延/18小时补封检测）"
```

---

### Task 4: Thumbnailer 与 MomentRepository

**Files:**
- Create: `Support/Thumbnailer.swift`
- Create: `Persistence/MomentRepository.swift`
- Test: `Tests/ThumbnailerTests.swift`、`Tests/MomentRepositoryTests.swift`

**Interfaces:**
- Consumes: T3 `dayForNewRecord`；`CDMoment/CDPhoto/CDEvaluation/CDPlace`；`MomentType`
- Produces: `Thumbnailer.thumbnailData(from:maxPixel:) -> Data?`；`NewEvaluation(stars:moodEmoji:comment:)`；`MomentRepository(context:)`：`create(in:type:title:body:happenedAt:photoDatas:myEvaluation:authorID:place:) -> CDMoment`、`update(_:type:title:body:happenedAt:)`、`delete(_:)`、`move(_:to:)`、`daysWithMoments(in:) -> [(day: CDDateDay, moments: [CDMoment])]`（天升序、天内按 happenedAt 升序）、`photosSorted(_:) -> [CDPhoto]`、`evaluation(of:by:) -> CDEvaluation?`

- [ ] **Step 1: 写失败测试**

`Tests/ThumbnailerTests.swift`:

```swift
import XCTest
import UIKit
@testable import Anniversary

final class ThumbnailerTests: XCTestCase {
    private func makeImageData(width: CGFloat, height: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { ctx in
            UIColor.systemRed.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    func testThumbnailDownsamplesLongEdgeTo600() throws {
        let original = makeImageData(width: 2000, height: 1000)

        let thumbData = try XCTUnwrap(Thumbnailer.thumbnailData(from: original))
        let thumb = try XCTUnwrap(UIImage(data: thumbData))

        let longEdge = max(thumb.size.width * thumb.scale, thumb.size.height * thumb.scale)
        XCTAssertLessThanOrEqual(longEdge, 600 + 1)
        XCTAssertLessThan(thumbData.count, original.count)
    }

    func testThumbnailReturnsNilForGarbage() {
        XCTAssertNil(Thumbnailer.thumbnailData(from: Data([0x00, 0x01, 0x02])))
    }
}
```

`Tests/MomentRepositoryTests.swift`:

```swift
import XCTest
import UIKit
@testable import Anniversary

final class MomentRepositoryTests: XCTestCase {
    private var pc: PersistenceController!
    private var meetings: MeetingRepository!
    private var moments: MomentRepository!
    private var couple: CDCouple!
    private var meeting: CDMeeting!
    private var creatorID: UUID!

    override func setUpWithError() throws {
        pc = PersistenceController(inMemory: true)
        let couples = CoupleRepository(context: pc.viewContext)
        couple = try couples.bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        creatorID = couples.creatorID(of: couple)
        meetings = MeetingRepository(context: pc.viewContext)
        moments = MomentRepository(context: pc.viewContext)
        meeting = try meetings.createPlanned(couple: couple, title: nil, city: "上海", plannedStart: nil, plannedEnd: nil)
        try meetings.start(meeting, at: Date(timeIntervalSince1970: 0))
    }

    private func imageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 800))
        return renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 800))
        }.jpegData(compressionQuality: 0.9)!
    }

    func testCreateAssignsOpenDayAndStoresPhotoWithThumbnail() throws {
        let data = imageData()
        let m = try moments.create(in: meeting, type: .restaurant, title: "蟹家大院", body: "排队四十分钟",
                                   happenedAt: Date(timeIntervalSince1970: 1_000),
                                   photoDatas: [data],
                                   myEvaluation: NewEvaluation(stars: 5, moodEmoji: "😋", comment: "封神"),
                                   authorID: creatorID, place: nil)

        XCTAssertEqual(m.dateDay?.dayIndex, 1)
        let photos = moments.photosSorted(m)
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos[0].imageData, data)
        XCTAssertNotNil(photos[0].thumbnailData)
        let eval = moments.evaluation(of: m, by: creatorID)
        XCTAssertEqual(eval?.stars, 5)
        XCTAssertEqual(eval?.comment, "封神")
    }

    func testDaysWithMomentsGroupsAndSorts() throws {
        _ = try moments.create(in: meeting, type: .sight, title: "外滩", body: nil,
                               happenedAt: Date(timeIntervalSince1970: 5_000),
                               photoDatas: [], myEvaluation: nil, authorID: creatorID, place: nil)
        _ = try moments.create(in: meeting, type: .restaurant, title: "早茶", body: nil,
                               happenedAt: Date(timeIntervalSince1970: 2_000),
                               photoDatas: [], myEvaluation: nil, authorID: creatorID, place: nil)
        try meetings.sealOpenDay(in: meeting, at: Date(timeIntervalSince1970: 40_000))
        _ = try moments.create(in: meeting, type: .activity, title: "桌游", body: nil,
                               happenedAt: Date(timeIntervalSince1970: 50_000),
                               photoDatas: [], myEvaluation: nil, authorID: creatorID, place: nil)

        let grouped = moments.daysWithMoments(in: meeting)
        XCTAssertEqual(grouped.map(\.day.dayIndex), [1, 2])
        XCTAssertEqual(grouped[0].moments.map(\.title), ["早茶", "外滩"])
        XCTAssertEqual(grouped[1].moments.map(\.title), ["桌游"])
    }

    func testMoveAndDelete() throws {
        let a = try moments.create(in: meeting, type: .other, title: "A", body: nil,
                                   happenedAt: Date(timeIntervalSince1970: 1_000),
                                   photoDatas: [], myEvaluation: nil, authorID: creatorID, place: nil)
        try meetings.sealOpenDay(in: meeting, at: Date(timeIntervalSince1970: 2_000))
        let b = try moments.create(in: meeting, type: .other, title: "B", body: nil,
                                   happenedAt: Date(timeIntervalSince1970: 3_000),
                                   photoDatas: [], myEvaluation: nil, authorID: creatorID, place: nil)
        let day1 = try XCTUnwrap(a.dateDay)

        try moments.move(b, to: day1)
        XCTAssertEqual(moments.daysWithMoments(in: meeting)[0].moments.map(\.title), ["A", "B"])

        try moments.delete(a)
        XCTAssertEqual(moments.daysWithMoments(in: meeting)[0].moments.map(\.title), ["B"])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL（Thumbnailer/MomentRepository 未定义）

- [ ] **Step 3: 实现 Thumbnailer**

`Support/Thumbnailer.swift`:

```swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Thumbnailer {
    /// 从原图数据生成长边 maxPixel 的 JPEG 缩略图；无法解码返回 nil
    static func thumbnailData(from imageData: Data, maxPixel: CGFloat = 600) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(imageData as CFData, sourceOptions) else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
```

- [ ] **Step 4: 实现 MomentRepository**

`Persistence/MomentRepository.swift`:

```swift
import CoreData

struct NewEvaluation {
    let stars: Int16
    let moodEmoji: String?
    let comment: String?
}

struct MomentRepository {
    let context: NSManagedObjectContext

    @discardableResult
    func create(in meeting: CDMeeting, type: MomentType, title: String, body: String?,
                happenedAt: Date, photoDatas: [Data], myEvaluation: NewEvaluation?,
                authorID: UUID?, place: CDPlace?) throws -> CDMoment {
        let day = try MeetingRepository(context: context).dayForNewRecord(in: meeting, at: happenedAt)

        let moment = CDMoment(context: context)
        moment.id = UUID()
        moment.typeRaw = type.rawValue
        moment.title = title
        moment.body = body
        moment.happenedAt = happenedAt
        moment.createdAt = Date()
        moment.authorPartnerID = authorID
        moment.dateDay = day
        moment.place = place

        for (i, data) in photoDatas.enumerated() {
            let photo = CDPhoto(context: context)
            photo.id = UUID()
            photo.imageData = data
            photo.thumbnailData = Thumbnailer.thumbnailData(from: data)
            photo.sortIndex = Int32(i)
            photo.moment = moment
        }

        if let ev = myEvaluation {
            let evaluation = CDEvaluation(context: context)
            evaluation.id = UUID()
            evaluation.authorPartnerID = authorID
            evaluation.stars = ev.stars
            evaluation.moodEmoji = ev.moodEmoji
            evaluation.comment = ev.comment
            evaluation.moment = moment
        }

        try context.save()
        return moment
    }

    func update(_ moment: CDMoment, type: MomentType, title: String, body: String?, happenedAt: Date) throws {
        moment.typeRaw = type.rawValue
        moment.title = title
        moment.body = body
        moment.happenedAt = happenedAt
        try context.save()
    }

    func delete(_ moment: CDMoment) throws {
        context.delete(moment)
        try context.save()
    }

    func move(_ moment: CDMoment, to day: CDDateDay) throws {
        moment.dateDay = day
        try context.save()
    }

    func daysWithMoments(in meeting: CDMeeting) -> [(day: CDDateDay, moments: [CDMoment])]{
        let days = ((meeting.dateDays as? Set<CDDateDay>) ?? [])
            .sorted { $0.dayIndex < $1.dayIndex }
        return days.map { day in
            let ms = ((day.moments as? Set<CDMoment>) ?? [])
                .sorted { ($0.happenedAt ?? .distantPast) < ($1.happenedAt ?? .distantPast) }
            return (day, ms)
        }
    }

    func photosSorted(_ moment: CDMoment) -> [CDPhoto] {
        ((moment.photos as? Set<CDPhoto>) ?? [])
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func evaluation(of moment: CDMoment, by authorID: UUID?) -> CDEvaluation? {
        ((moment.evaluations as? Set<CDEvaluation>) ?? [])
            .first { $0.authorPartnerID == authorID }
    }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `./scripts/gen.sh && ./scripts/test.sh`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Support/Thumbnailer.swift Persistence/MomentRepository.swift Tests/ThumbnailerTests.swift Tests/MomentRepositoryTests.swift
git commit -m "添加缩略图生成与记忆仓库（自动归日/照片/评价）"
```

---

### Task 5: PlanItemRepository 排序规则

**Files:**
- Create: `Persistence/PlanItemRepository.swift`
- Test: `Tests/PlanItemRepositoryTests.swift`

**Interfaces:**
- Consumes: `CDMeeting/CDPlanItem`
- Produces: `PlanSections(dated: [(day: Date, items: [CDPlanItem])], undated: [CDPlanItem])`；`PlanItemRepository(context:)`：`add(to:day:time:title:note:placeText:authorID:) -> CDPlanItem`（sortIndex 会内自增）、`toggleDone(_:)`、`update(_:day:time:title:note:placeText:)`、`delete(_:)`、`sections(for:calendar:) -> PlanSections`、`stats(for:) -> (planned: Int, done: Int)`

- [ ] **Step 1: 写失败测试**

`Tests/PlanItemRepositoryTests.swift`:

```swift
import XCTest
@testable import Anniversary

final class PlanItemRepositoryTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: PlanItemRepository!
    private var meeting: CDMeeting!
    private let cal = Calendar(identifier: .gregorian)

    override func setUpWithError() throws {
        pc = PersistenceController(inMemory: true)
        let couple = try CoupleRepository(context: pc.viewContext)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        meeting = try MeetingRepository(context: pc.viewContext)
            .createPlanned(couple: couple, title: nil, city: "上海", plannedStart: nil, plannedEnd: nil)
        repo = PlanItemRepository(context: pc.viewContext)
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testSectionsSortRule() throws {
        // 规则：日期升序 → 同日内全天(无时间)在前、有时间按时间升序、再按 sortIndex → 无日期归备忘区按 sortIndex
        _ = try repo.add(to: meeting, day: date(2026, 8, 30), time: date(2026, 8, 30, 19, 30),
                         title: "辉哥火锅", note: nil, placeText: nil, authorID: nil)
        _ = try repo.add(to: meeting, day: date(2026, 8, 30), time: nil,
                         title: "迪士尼", note: nil, placeText: nil, authorID: nil)
        _ = try repo.add(to: meeting, day: date(2026, 8, 29), time: date(2026, 8, 29, 14, 0),
                         title: "高铁", note: nil, placeText: nil, authorID: nil)
        _ = try repo.add(to: meeting, day: nil, time: nil,
                         title: "带充电宝", note: nil, placeText: nil, authorID: nil)
        _ = try repo.add(to: meeting, day: nil, time: nil,
                         title: "晕车药", note: nil, placeText: nil, authorID: nil)

        let s = repo.sections(for: meeting, calendar: cal)

        XCTAssertEqual(s.dated.count, 2)
        XCTAssertEqual(s.dated[0].items.map(\.title), ["高铁"])
        XCTAssertEqual(s.dated[1].items.map(\.title), ["迪士尼", "辉哥火锅"])
        XCTAssertEqual(s.undated.map(\.title), ["带充电宝", "晕车药"])
    }

    func testToggleAndStats() throws {
        let a = try repo.add(to: meeting, day: nil, time: nil, title: "订酒店", note: nil, placeText: nil, authorID: nil)
        _ = try repo.add(to: meeting, day: nil, time: nil, title: "订车票", note: nil, placeText: nil, authorID: nil)

        try repo.toggleDone(a)
        var st = repo.stats(for: meeting)
        XCTAssertEqual(st.planned, 2)
        XCTAssertEqual(st.done, 1)

        try repo.toggleDone(a)
        st = repo.stats(for: meeting)
        XCTAssertEqual(st.done, 0)
    }

    func testUpdateAndDelete() throws {
        let a = try repo.add(to: meeting, day: nil, time: nil, title: "旧", note: nil, placeText: nil, authorID: nil)
        try repo.update(a, day: date(2026, 8, 29), time: nil, title: "新", note: "备注", placeText: "湖滨路店")
        XCTAssertEqual(a.title, "新")
        XCTAssertEqual(repo.sections(for: meeting, calendar: cal).dated.count, 1)

        try repo.delete(a)
        XCTAssertEqual(repo.stats(for: meeting).planned, 0)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL（PlanItemRepository 未定义）

- [ ] **Step 3: 实现**

`Persistence/PlanItemRepository.swift`:

```swift
import CoreData

struct PlanSections {
    let dated: [(day: Date, items: [CDPlanItem])]
    let undated: [CDPlanItem]
}

struct PlanItemRepository {
    let context: NSManagedObjectContext

    @discardableResult
    func add(to meeting: CDMeeting, day: Date?, time: Date?, title: String,
             note: String?, placeText: String?, authorID: UUID?) throws -> CDPlanItem {
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
        item.sortIndex = maxSort + 1
        item.meeting = meeting
        try context.save()
        return item
    }

    func toggleDone(_ item: CDPlanItem) throws {
        item.isDone.toggle()
        try context.save()
    }

    func update(_ item: CDPlanItem, day: Date?, time: Date?, title: String,
                note: String?, placeText: String?) throws {
        item.day = day
        item.time = time
        item.title = title
        item.note = note
        item.placeText = placeText
        try context.save()
    }

    func delete(_ item: CDPlanItem) throws {
        context.delete(item)
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
                case let (ta?, tb?): return ta != tb ? ta < tb : a.sortIndex < b.sortIndex
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
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `./scripts/gen.sh && ./scripts/test.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Persistence/PlanItemRepository.swift Tests/PlanItemRepositoryTests.swift
git commit -m "添加行前计划仓库并测试锁死排序规则"
```

---

### Task 6: DailyMood 与首页逻辑

**Files:**
- Create: `Support/HomeLogic.swift`
- Create: `Persistence/DailyMoodRepository.swift`
- Test: `Tests/HomeLogicTests.swift`、`Tests/DailyMoodRepositoryTests.swift`

**Interfaces:**
- Consumes: `CDCouple/CDDailyMood`
- Produces: `HomeLogic.daysTogether(anniversary:today:calendar:) -> Int`（首日=第 1 天）、`HomeLogic.countdownDays(to:from:calendar:) -> Int`（按自然日、当天=0、不为负）、`HomeLogic.daysToNextAnniversary(anniversary:today:calendar:) -> Int`；`DailyMoodRepository(context:)`：`setMood(couple:authorID:day:emoji:note:calendar:) -> CDDailyMood`（按 作者+自然日 幂等 upsert）、`mood(couple:authorID:day:calendar:) -> CDDailyMood?`

- [ ] **Step 1: 写失败测试**

`Tests/HomeLogicTests.swift`:

```swift
import XCTest
@testable import Anniversary

final class HomeLogicTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    func testDaysTogetherInclusive() {
        let anniversary = date(2025, 6, 9)
        XCTAssertEqual(HomeLogic.daysTogether(anniversary: anniversary, today: date(2025, 6, 9), calendar: cal), 1)
        XCTAssertEqual(HomeLogic.daysTogether(anniversary: anniversary, today: date(2025, 6, 10), calendar: cal), 2)
        XCTAssertEqual(HomeLogic.daysTogether(anniversary: anniversary, today: date(2026, 7, 25), calendar: cal), 412)
    }

    func testCountdownDays() {
        XCTAssertEqual(HomeLogic.countdownDays(to: date(2026, 8, 29), from: date(2026, 8, 17), calendar: cal), 12)
        XCTAssertEqual(HomeLogic.countdownDays(to: date(2026, 8, 29), from: date(2026, 8, 29, 23), calendar: cal), 0)
        XCTAssertEqual(HomeLogic.countdownDays(to: date(2026, 8, 29), from: date(2026, 9, 1), calendar: cal), 0)
    }

    func testDaysToNextAnniversary() {
        let anniversary = date(2025, 6, 9)
        XCTAssertEqual(HomeLogic.daysToNextAnniversary(anniversary: anniversary, today: date(2026, 6, 1), calendar: cal), 8)
        XCTAssertEqual(HomeLogic.daysToNextAnniversary(anniversary: anniversary, today: date(2026, 6, 9), calendar: cal), 0)
        XCTAssertEqual(HomeLogic.daysToNextAnniversary(anniversary: anniversary, today: date(2026, 6, 10), calendar: cal), 364)
    }
}
```

`Tests/DailyMoodRepositoryTests.swift`:

```swift
import XCTest
@testable import Anniversary

final class DailyMoodRepositoryTests: XCTestCase {
    func testSetMoodUpsertsPerAuthorPerDay() throws {
        let pc = PersistenceController(inMemory: true)
        let couples = CoupleRepository(context: pc.viewContext)
        let couple = try couples.bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        let me = couples.creatorID(of: couple)
        let repo = DailyMoodRepository(context: pc.viewContext)
        let cal = Calendar(identifier: .gregorian)
        let morning = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 9))!
        let evening = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 21))!

        _ = try repo.setMood(couple: couple, authorID: me, day: morning, emoji: "😊", note: nil, calendar: cal)
        _ = try repo.setMood(couple: couple, authorID: me, day: evening, emoji: "🥰", note: "见面了", calendar: cal)

        let all = (couple.dailyMoods as? Set<CDDailyMood>) ?? []
        XCTAssertEqual(all.count, 1)
        let found = repo.mood(couple: couple, authorID: me, day: evening, calendar: cal)
        XCTAssertEqual(found?.moodEmoji, "🥰")
        XCTAssertEqual(found?.note, "见面了")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL（HomeLogic/DailyMoodRepository 未定义）

- [ ] **Step 3: 实现 HomeLogic**

`Support/HomeLogic.swift`:

```swift
import Foundation

enum HomeLogic {
    /// 在一起第 N 天：纪念日当天 = 第 1 天（含首日）
    static func daysTogether(anniversary: Date, today: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: anniversary)
        let to = calendar.startOfDay(for: today)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        return max(days + 1, 1)
    }

    /// 距目标日期还有几天（按自然日，当天=0，过期归 0）
    static func countdownDays(to target: Date, from today: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: today)
        let to = calendar.startOfDay(for: target)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        return max(days, 0)
    }

    /// 距下一个周年纪念日的天数（当天=0）
    static func daysToNextAnniversary(anniversary: Date, today: Date, calendar: Calendar) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        let comps = calendar.dateComponents([.month, .day], from: anniversary)
        var next = calendar.nextDate(after: todayStart.addingTimeInterval(-1),
                                     matching: comps, matchingPolicy: .nextTime) ?? todayStart
        if calendar.startOfDay(for: next) < todayStart {
            next = calendar.date(byAdding: .year, value: 1, to: next) ?? next
        }
        return countdownDays(to: next, from: today, calendar: calendar)
    }
}
```

- [ ] **Step 4: 实现 DailyMoodRepository**

`Persistence/DailyMoodRepository.swift`:

```swift
import CoreData

struct DailyMoodRepository {
    let context: NSManagedObjectContext

    @discardableResult
    func setMood(couple: CDCouple, authorID: UUID?, day: Date, emoji: String,
                 note: String?, calendar: Calendar) throws -> CDDailyMood {
        let normalized = calendar.startOfDay(for: day)
        let mood: CDDailyMood
        if let existing = self.mood(couple: couple, authorID: authorID, day: day, calendar: calendar) {
            mood = existing
        } else {
            mood = CDDailyMood(context: context)
            mood.id = UUID()
            mood.authorPartnerID = authorID
            mood.day = normalized
            mood.couple = couple
        }
        mood.moodEmoji = emoji
        mood.note = note
        try context.save()
        return mood
    }

    func mood(couple: CDCouple, authorID: UUID?, day: Date, calendar: Calendar) -> CDDailyMood? {
        let normalized = calendar.startOfDay(for: day)
        return ((couple.dailyMoods as? Set<CDDailyMood>) ?? [])
            .first { $0.authorPartnerID == authorID && $0.day == normalized }
    }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `./scripts/gen.sh && ./scripts/test.sh`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Support/HomeLogic.swift Persistence/DailyMoodRepository.swift Tests/HomeLogicTests.swift Tests/DailyMoodRepositoryTests.swift
git commit -m "添加首页日期逻辑与每日心情仓库（按日幂等）"
```

---

### Task 7: Tab 壳、⊕ 动作面板与公共小件

**Files:**
- Create: `App/MainShell.swift`、`App/ActionPanel.swift`
- Create: `Support/Formatters.swift`、`DesignSystem/DSExtras.swift`
- Modify: `project.yml`（Anniversary target 的 sources 数组追加一行 `- Features`；同时创建空目录占位 `Features/.gitkeep`，T8 起放真实文件）

**Interfaces:**
- Consumes: P0 设计系统组件；T2 `ongoingMeeting`
- Produces: `MainShell`（根壳）；`PanelAction { newMoment, mood, seal }`；`ActionPanel(hasOngoing:onAction:)`；`Fmt.ymd/.monthDay/.monthDayWeek/.hm`（zh_CN DateFormatter）；`dsMoodEmojis: [String]`；`AvatarInitial(name:size:)`、`StarsView(stars:size:)`、`StarInputView(stars:)`、`EmojiPickerRow(selection:)`。本任务里 MainShell 引用的 `HomeView/MeetingsView/MomentFormView/MoodSheet/SealSheet` 均以最小占位实现同文件内私有定义？——不。为避免占位反模式，本任务 MainShell 的两个 Tab 内容暂显示 `DSGallery()` 与 `Text("足迹 · T10 接入")`，⊕ 动作回调仅 `print`；T9/T10/T12/T13 逐步替换接线（每次替换都在对应任务的 Modify 步骤中明确给出）。RootView 本任务不动（仍显示画廊），T8 才切换路由。

- [ ] **Step 1: 写 Formatters.swift**

```swift
import Foundation

enum Fmt {
    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = format
        return f
    }

    static let ymd = make("yyyy.MM.dd")
    static let monthDay = make("M月d日")
    static let monthDayWeek = make("M月d日 EEE")
    static let hm = make("HH:mm")
}
```

- [ ] **Step 2: 写 DSExtras.swift**

```swift
import SwiftUI

let dsMoodEmojis = ["😊", "🥰", "😍", "😌", "🤣", "😴", "😢", "😡"]

struct AvatarInitial: View {
    let name: String
    var size: CGFloat = 24

    var body: some View {
        Circle()
            .fill(DS.parchment)
            .overlay(Circle().stroke(DS.hairline, lineWidth: 1))
            .overlay(
                Text(name.isEmpty ? "?" : String(name.prefix(1)))
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(DS.ink)
            )
            .frame(width: size, height: size)
    }
}

struct StarsView: View {
    let stars: Int
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: "star.fill")
                    .font(.system(size: size))
                    .foregroundStyle(i <= stars ? DS.ink : DS.chipBorder)
            }
        }
    }
}

struct StarInputView: View {
    @Binding var stars: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    stars = i
                } label: {
                    Image(systemName: "star.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(i <= stars ? DS.actionBlue : DS.chipBorder)
                }
                .buttonStyle(DSPressEffect())
            }
        }
    }
}

struct EmojiPickerRow: View {
    @Binding var selection: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
            ForEach(dsMoodEmojis, id: \.self) { emoji in
                Button {
                    selection = emoji
                } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(DS.canvas))
                        .overlay(
                            Circle().stroke(
                                selection == emoji ? DS.focusBlue : DS.hairline,
                                lineWidth: selection == emoji ? 2 : 1
                            )
                        )
                }
                .buttonStyle(DSPressEffect())
            }
        }
    }
}
```

- [ ] **Step 3: 写 ActionPanel.swift**

```swift
import SwiftUI

enum PanelAction {
    case newMoment
    case mood
    case seal
}

struct ActionPanel: View {
    let hasOngoing: Bool
    let onAction: (PanelAction) -> Void

    private struct Tile {
        let symbol: String
        let title: String
        let action: PanelAction?
    }

    private var tiles: [Tile] {
        [
            Tile(symbol: "photo.on.rectangle", title: "记忆", action: .newMoment),
            Tile(symbol: "square.and.pencil", title: "互评", action: nil),
            Tile(symbol: "face.smiling", title: "心情", action: .mood),
            Tile(symbol: "heart", title: "喜怒", action: nil),
            Tile(symbol: "sparkles", title: "亲密", action: nil),
            Tile(symbol: "drop", title: "经期", action: nil),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("记一笔").dsSectionTitle()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(tiles, id: \.title) { tile in
                    Button {
                        if let action = tile.action { onAction(action) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tile.symbol)
                                .font(.system(size: 18))
                                .foregroundStyle(DS.actionBlue)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(DS.canvas))
                            Text(tile.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment))
                    }
                    .buttonStyle(DSPressEffect())
                    .disabled(tile.action == nil)
                    .opacity(tile.action == nil ? 0.35 : 1)
                }
            }
            if hasOngoing {
                Button("封盘") { onAction(.seal) }
                    .buttonStyle(BluePillButtonStyle(fullWidth: true))
            }
            Text(hasOngoing ? "封盘：今天到此为止，晚安" : "灰色入口在后续阶段开启")
                .dsFootnote()
                .frame(maxWidth: .infinity)
        }
        .padding(DS.Spacing.md)
        .presentationDetents([.height(hasOngoing ? 340 : 300)])
        .presentationCornerRadius(20)
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ActionPanel(hasOngoing: true) { _ in }
    }
}
```

- [ ] **Step 4: 写 MainShell.swift**

```swift
import SwiftUI
import CoreData

enum AppTab {
    case us
    case footprints
}

struct MainShell: View {
    @Environment(\.managedObjectContext) private var context
    @State private var tab: AppTab = .us
    @State private var showPanel = false
    @State private var activeSheet: ShellSheet?

    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "statusRaw == %d", MeetingStatus.ongoing.rawValue)
    ) private var ongoingMeetings: FetchedResults<CDMeeting>

    enum ShellSheet: Identifiable {
        case newMoment(CDMeeting)
        case mood
        case seal(CDMeeting)

        var id: String {
            switch self {
            case .newMoment: "newMoment"
            case .mood: "mood"
            case .seal: "seal"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch tab {
                case .us: NavigationStack { DSGallery() }          // T9 接入 HomeView
                case .footprints: NavigationStack { Text("足迹 · T10 接入").dsCaption() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showPanel) {
            ActionPanel(hasOngoing: ongoingMeetings.first != nil) { action in
                showPanel = false
                handle(action)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newMoment, .mood, .seal:
                Text("动作占位 · 后续任务接线").dsCaption().padding()  // T9/T12/T13 替换
            }
        }
    }

    private func handle(_ action: PanelAction) {
        switch action {
        case .newMoment:
            if let meeting = ongoingMeetings.first { activeSheet = .newMoment(meeting) }
        case .mood:
            activeSheet = .mood
        case .seal:
            if let meeting = ongoingMeetings.first { activeSheet = .seal(meeting) }
        }
    }

    private var bottomBar: some View {
        FrostedBottomBar {
            HStack {
                tabButton("我们", tab: .us)
                Spacer()
                tabButton("足迹", tab: .footprints)
                Spacer()
                Button {
                    showPanel = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(DS.actionBlue))
                        .rotationEffect(.degrees(showPanel ? 45 : 0))
                        .animation(.easeOut(duration: 0.2), value: showPanel)
                }
                .buttonStyle(DSPressEffect())
                .offset(y: -8)
                Spacer()
                disabledTab("小本本")
                Spacer()
                disabledTab("她")
            }
        }
    }

    private func tabButton(_ title: String, tab target: AppTab) -> some View {
        Button {
            tab = target
        } label: {
            Text(title)
                .font(.system(size: 13, weight: tab == target ? .semibold : .regular))
                .foregroundStyle(tab == target ? DS.actionBlue : DS.inkMuted)
        }
        .buttonStyle(DSPressEffect())
    }

    private func disabledTab(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundStyle(DS.inkMuted)
            .opacity(0.35)
    }
}
```

（本任务的两处"占位"文本只存在于壳内部、且各自的替换步骤在 T9/T10/T12/T13 中有明确 Modify 指令，不属于计划级 placeholder。）

- [ ] **Step 5: project.yml 加 Features 源目录**

`project.yml` 的 Anniversary target `sources:` 数组中 `- App` 之后追加一行 `      - Features`；执行 `mkdir -p Features && touch Features/.gitkeep`。

- [ ] **Step 6: 构建验证**

Run: `./scripts/gen.sh && ./scripts/build.sh`
Expected: `✅ 构建通过`

- [ ] **Step 7: Commit**

```bash
git add App DesignSystem/DSExtras.swift Support/Formatters.swift project.yml Features
git commit -m "添加主壳与动作面板及公共小件（Tab/格式化/头像/星星/表情）"
```

---

### Task 8: 引导页（单机创建空间）

**Files:**
- Create: `Features/Onboarding/OnboardingView.swift`
- Modify: `App/RootView.swift`（全文替换）
- Delete: `Features/.gitkeep`

**Interfaces:**
- Consumes: `CoupleRepository.bootstrapIfNeeded`；DS 组件
- Produces: `OnboardingView`；RootView 路由：无 Couple → OnboardingView，有 → MainShell

- [ ] **Step 1: 写 OnboardingView.swift**

```swift
import SwiftUI

struct OnboardingView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var myName = ""
    @State private var partnerName = ""
    @State private var anniversary = Date()

    private var canCreate: Bool {
        !myName.trimmingCharacters(in: .whitespaces).isEmpty
            && !partnerName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                RoundedRectangle(cornerRadius: DS.Radius.large)
                    .fill(DS.parchment)
                    .frame(height: 220)
                    .overlay(
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(DS.actionBlue)
                    )

                VStack(spacing: 6) {
                    Text("我们的小宇宙").dsHero()
                    Text("记录每一次见面、每一顿饭、每一种心情。\n数据只存在你的设备上。")
                        .dsCaption()
                        .multilineTextAlignment(.center)
                }

                GroupedSection {
                    HStack {
                        Text("我的昵称").dsBody()
                        TextField("阿铖", text: $myName)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    DS.hairline.frame(height: 1).padding(.leading, 14)
                    HStack {
                        Text("TA 的昵称").dsBody()
                        TextField("小于", text: $partnerName)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    DS.hairline.frame(height: 1).padding(.leading, 14)
                    DatePicker("在一起的日子", selection: $anniversary,
                               in: ...Date(), displayedComponents: .date)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                }

                Button("创建我们的空间") {
                    try? CoupleRepository(context: context)
                        .bootstrapIfNeeded(myName: myName.trimmingCharacters(in: .whitespaces),
                                           partnerName: partnerName.trimmingCharacters(in: .whitespaces),
                                           anniversary: anniversary)
                }
                .buttonStyle(BluePillButtonStyle(fullWidth: true))
                .disabled(!canCreate)
                .opacity(canCreate ? 1 : 0.4)

                Text("P2 阶段这里会出现「接受 TA 的邀请」").dsFootnote()
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
    }
}

#Preview {
    OnboardingView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
```

- [ ] **Step 2: RootView 全文替换**

```swift
import SwiftUI

struct RootView: View {
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>

    var body: some View {
        if couples.isEmpty {
            OnboardingView()
        } else {
            MainShell()
        }
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PreviewData.makeController().viewContext)
}
```

- [ ] **Step 3: 构建验证**

Run: `rm -f Features/.gitkeep && ./scripts/gen.sh && ./scripts/build.sh`
Expected: `✅ 构建通过`

- [ ] **Step 4: Commit**

```bash
git add Features App/RootView.swift
git commit -m "添加单机引导页并接通根路由"
```

---

### Task 9: 首页（含心情打卡）

**Files:**
- Create: `Features/Home/HomeView.swift`、`Features/Home/MoodSheet.swift`
- Modify: `App/MainShell.swift`（两处：us Tab 换 HomeView；`.mood` sheet 换 MoodSheet）

**Interfaces:**
- Consumes: T1 `creatorID`、T2 `nextPlannedMeeting/ongoingMeeting`、T3 `staleOpenDay/daysSorted`、T5 `stats`、T6 全部、`Fmt`、DS 组件
- Produces: `HomeView`（本任务不含 gear 设置入口——T15 的 Modify 步骤会把 gear 补进 header；按执行顺序 T9 在 T11/T13 之后，`PlanView/MeetingDetailView` 均已存在，无前向引用）；`MoodSheet(couple:)`

- [ ] **Step 1: 写 MoodSheet.swift**

```swift
import SwiftUI

struct MoodSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let couple: CDCouple
    @State private var emoji: String?
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("今日心情").dsSectionTitle()
            EmojiPickerRow(selection: $emoji)
            TextField("想说一句吗（可选）", text: $note)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment))
            Button("保存") {
                if let emoji {
                    let repo = CoupleRepository(context: context)
                    try? DailyMoodRepository(context: context).setMood(
                        couple: couple, authorID: repo.creatorID(of: couple),
                        day: Date(), emoji: emoji,
                        note: note.isEmpty ? nil : note, calendar: .current)
                }
                dismiss()
            }
            .buttonStyle(BluePillButtonStyle(fullWidth: true))
            .disabled(emoji == nil)
            .opacity(emoji == nil ? 0.4 : 1)
        }
        .padding(DS.Spacing.md)
        .presentationDetents([.height(300)])
        .presentationCornerRadius(20)
        .presentationDragIndicator(.visible)
        .onAppear {
            let repo = CoupleRepository(context: context)
            if let existing = DailyMoodRepository(context: context).mood(
                couple: couple, authorID: repo.creatorID(of: couple), day: Date(), calendar: .current) {
                emoji = existing.moodEmoji
                note = existing.note ?? ""
            }
        }
    }
}
```

- [ ] **Step 2: 写 HomeView.swift**

```swift
import SwiftUI
import CoreData

struct HomeView: View {
    @Environment(\.managedObjectContext) private var context
    @AppStorage("showCountdown") private var showCountdown = true
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDMeeting.index, order: .reverse)])
    private var meetings: FetchedResults<CDMeeting>
    @FetchRequest(sortDescriptors: []) private var moods: FetchedResults<CDDailyMood>
    @State private var showMoodSheet = false

    private var couple: CDCouple? { couples.first }

    var body: some View {
        ScrollView {
            if let couple {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    header(couple)
                    hero(couple)
                    statusCard(couple)
                    moodCard(couple)
                    reminders(couple)
                }
                .padding(DS.Spacing.md)
            }
        }
        .background(DS.canvas)
        .sheet(isPresented: $showMoodSheet) {
            if let couple { MoodSheet(couple: couple) }
        }
    }

    private func header(_ couple: CDCouple) -> some View {
        let partners = CoupleRepository(context: context).partners(of: couple)
        return HStack {
            HStack(spacing: -6) {
                ForEach(partners, id: \.objectID) { p in
                    AvatarInitial(name: p.name ?? "", size: 28)
                }
            }
            Spacer()
        }
    }

    private func hero(_ couple: CDCouple) -> some View {
        VStack(spacing: 4) {
            Text("我们的时光").dsFootnote()
            if let anniversary = couple.anniversaryDate {
                let days = HomeLogic.daysTogether(anniversary: anniversary, today: Date(), calendar: .current)
                Text("在一起 \(days) 天")
                    .dsHero()
                    .contentTransition(.numericText())
                let toNext = HomeLogic.daysToNextAnniversary(anniversary: anniversary, today: Date(), calendar: .current)
                Text("\(Fmt.ymd.string(from: anniversary)) · 距纪念日还有 \(toNext) 天")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.actionBlue)
            } else {
                Text("在设置里填上在一起的日子").dsCaption()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm)
    }

    @ViewBuilder
    private func statusCard(_ couple: CDCouple) -> some View {
        let repo = MeetingRepository(context: context)
        let ongoing = meetings.first { $0.statusRaw == MeetingStatus.ongoing.rawValue }
        let planned = try? repo.nextPlannedMeeting(couple: couple, after: Calendar.current.startOfDay(for: Date()))

        if let ongoing {
            let dayIndex = (try? repo.daysSorted(in: ongoing).last?.dayIndex) ?? 0
            NavigationLink {
                MeetingDetailView(meeting: ongoing)
            } label: {
                DarkCard {
                    VStack(spacing: 4) {
                        Text("第 \(ongoing.index) 次见面 · 进行中")
                            .font(.system(size: 13)).foregroundStyle(DS.onDarkMuted)
                        Text(dayIndex > 0 ? "第 \(dayIndex) 天" : "还没开始记录")
                            .font(.system(size: 30, weight: .semibold)).tracking(-0.6)
                        Text("点开看时间线 ›")
                            .font(.system(size: 13)).foregroundStyle(DS.skyBlue)
                    }
                }
            }
            .buttonStyle(DSPressEffect())
        } else if showCountdown, let planned, let start = planned.plannedStart {
            let days = HomeLogic.countdownDays(to: start, from: Date(), calendar: .current)
            let stats = PlanItemRepository(context: context).stats(for: planned)
            NavigationLink {
                PlanView(meeting: planned)
            } label: {
                DarkCard {
                    VStack(spacing: 4) {
                        Text("距下次见面").font(.system(size: 13)).foregroundStyle(DS.onDarkMuted)
                        Text("\(days) 天")
                            .font(.system(size: 34, weight: .semibold)).tracking(-0.8)
                            .contentTransition(.numericText())
                        Text("查看行前计划 · 已安排 \(stats.planned) 项 ›")
                            .font(.system(size: 13)).foregroundStyle(DS.skyBlue)
                    }
                }
            }
            .buttonStyle(DSPressEffect())
        } else {
            DarkCard {
                VStack(spacing: 4) {
                    Text("还没有计划中的见面").font(.system(size: 13)).foregroundStyle(DS.onDarkMuted)
                    Text("去足迹页计划一次吧").font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }

    private func moodCard(_ couple: CDCouple) -> some View {
        let repo = CoupleRepository(context: context)
        let partners = repo.partners(of: couple)
        let mine = DailyMoodRepository(context: context)
            .mood(couple: couple, authorID: partners.first?.id, day: Date(), calendar: .current)
        return Button {
            showMoodSheet = true
        } label: {
            ParchmentCard {
                HStack(spacing: 8) {
                    Text("今日心情").dsCaption()
                    if let emoji = mine?.moodEmoji {
                        Text(emoji).font(.system(size: 18))
                    } else {
                        Circle().stroke(DS.chipBorder, style: StrokeStyle(lineWidth: 1, dash: [3]))
                            .frame(width: 24, height: 24)
                            .overlay(Text("+").dsCaption())
                    }
                    Spacer()
                    Text(partners.count > 1 ? "\(partners[1].name ?? "TA") 还没打卡" : "")
                        .dsFootnote()
                }
            }
        }
        .buttonStyle(DSPressEffect())
    }

    @ViewBuilder
    private func reminders(_ couple: CDCouple) -> some View {
        let repo = MeetingRepository(context: context)
        let ongoing = meetings.first { $0.statusRaw == MeetingStatus.ongoing.rawValue }
        let stale = ongoing.flatMap { try? repo.staleOpenDay(in: $0, now: Date()) } ?? nil

        Text("提醒").dsSectionTitle()
        GroupedSection {
            if let ongoing, stale != nil {
                NavigationLink {
                    MeetingDetailView(meeting: ongoing)
                } label: {
                    GroupedRow(title: "昨天忘了封盘？", value: "去封盘 ›",
                               valueColor: DS.actionBlue, showsDivider: false)
                }
                .buttonStyle(.plain)
            } else {
                GroupedRow(title: "一切都好", value: "去足迹翻翻回忆 ›", showsDivider: false)
            }
        }
    }
}
```

- [ ] **Step 3: MainShell 接线（Modify）**

`App/MainShell.swift`：
1. `case .us: NavigationStack { DSGallery() }` 改为 `case .us: NavigationStack { HomeView() }`（DSGallery 保留在代码库，仅 Preview 可达）。
2. `.sheet(item: $activeSheet)` 内 `case .mood:` 分支改为：

```swift
            case .mood:
                if let couple = try? CoupleRepository(context: context).fetchCouple() {
                    MoodSheet(couple: couple)
                }
```

（switch 三分支已由 T13 拆开；本步骤只动 `.mood` 分支，`.newMoment` 留待 T12 替换。）

- [ ] **Step 4: 构建验证**

Run: `./scripts/gen.sh && ./scripts/build.sh`
Expected: `✅ 构建通过`（注意：HomeView 引用了 `MeetingDetailView/PlanView`，它们在 T13/T11 才创建——**因此本任务的构建顺序必须调整**：见下方任务顺序说明）

> **任务顺序说明（对执行者）**：T9 依赖 T11 的 `PlanView` 与 T13 的 `MeetingDetailView` 才能编译。执行顺序为 **T7 → T8 → T10 → T11 → T13 → T9 → T12 → T14 → T15 → T16**（本文档按功能归组书写，执行按此顺序）。控制器派发时按该顺序取任务号。

- [ ] **Step 5: Commit**

```bash
git add Features/Home App/MainShell.swift
git commit -m "添加首页与心情打卡并接入主壳"
```

---

### Task 10: 见面列表与计划见面表单

**Files:**
- Create: `Features/Meetings/MeetingsView.swift`、`Features/Meetings/MeetingFormView.swift`
- Modify: `App/MainShell.swift`（footprints Tab 换 MeetingsView）

**Interfaces:**
- Consumes: T2 仓库、T4 `daysWithMoments/photosSorted`、T5 `stats`、`Fmt`
- Produces: `MeetingsView`；`MeetingFormView`（sheet 表单）。**分两段执行**：Step 1–4（任务号 T10 首次派发）产出纯展示卡片列表与表单，不含跳转；Step 5 是"回接段"，在 T11/T13 完成后作为独立小任务派发，给三种卡片包上 NavigationLink（目的地 `PlanView`/`MeetingDetailView` 届时已存在）。两段各自构建验证、各自 commit。

- [ ] **Step 1: 写 MeetingFormView.swift**

```swift
import SwiftUI

struct MeetingFormView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let couple: CDCouple
    @State private var title = ""
    @State private var city = ""
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Calendar.current.startOfDay(for: Date())

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
                        DatePicker("开始日期", selection: $start, displayedComponents: .date)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        DatePicker("结束日期", selection: $end, in: start..., displayedComponents: .date)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle("计划见面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        try? MeetingRepository(context: context).createPlanned(
                            couple: couple,
                            title: title.isEmpty ? nil : title,
                            city: city.isEmpty ? nil : city,
                            plannedStart: start, plannedEnd: end)
                        dismiss()
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: 写 MeetingsView.swift**

```swift
import SwiftUI
import CoreData

struct MeetingsView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDMeeting.index, order: .reverse)])
    private var meetings: FetchedResults<CDMeeting>
    @State private var showForm = false

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.md) {
                ForEach(meetings, id: \.objectID) { meeting in
                    card(for: meeting)
                }
                if meetings.isEmpty {
                    Text("还没有见面记录").dsCaption().padding(.top, 48)
                }
                Button("计划见面") { showForm = true }
                    .buttonStyle(GhostPillButtonStyle())
                    .padding(.top, DS.Spacing.xs)
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .navigationTitle("足迹")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showForm) {
            if let couple = couples.first { MeetingFormView(couple: couple) }
        }
    }

    private func dateRange(_ m: CDMeeting) -> String {
        let s = m.startedAt ?? m.plannedStart
        let e = m.endedAt ?? m.plannedEnd
        switch (s, e) {
        case let (s?, e?): return "\(Fmt.monthDay.string(from: s)) – \(Fmt.monthDay.string(from: e))"
        case let (s?, nil): return Fmt.monthDay.string(from: s)
        default: return "日期待定"
        }
    }

    @ViewBuilder
    private func card(for meeting: CDMeeting) -> some View {
        switch MeetingStatus(rawValue: meeting.statusRaw) ?? .planned {
        case .planned:
            plannedCard(meeting)
        case .ongoing:
            ongoingCard(meeting)
        case .finished:
            finishedCard(meeting)
        }
    }

    private func plannedCard(_ meeting: CDMeeting) -> some View {
        let stats = PlanItemRepository(context: context).stats(for: meeting)
        let days = meeting.plannedStart.map {
            HomeLogic.countdownDays(to: $0, from: Date(), calendar: .current)
        }
        return ParchmentCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("第 \(meeting.index) 次见面 · 计划中").dsFootnote()
                Text([meeting.city, meeting.title].compactMap { $0 }.joined(separator: " · ")
                     .isEmpty ? "未命名的见面" : [meeting.city, meeting.title].compactMap { $0 }.joined(separator: " · "))
                    .dsPageTitle()
                HStack {
                    Text("\(dateRange(meeting)) · 行前计划 \(stats.done)/\(stats.planned)").dsCaption()
                    Spacer()
                    if let days {
                        Text("\(days) 天后")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 4).padding(.horizontal, 12)
                            .background(Capsule().fill(DS.actionBlue))
                    }
                }
            }
        }
    }

    private func ongoingCard(_ meeting: CDMeeting) -> some View {
        DarkCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("第 \(meeting.index) 次见面 · 进行中")
                    .font(.system(size: 13)).foregroundStyle(DS.onDarkMuted)
                Text(meeting.city ?? meeting.title ?? "这次见面")
                    .font(.system(size: 22, weight: .semibold)).tracking(-0.4)
                Text(dateRange(meeting)).font(.system(size: 13)).foregroundStyle(DS.skyBlue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func finishedCard(_ meeting: CDMeeting) -> some View {
        let momentsRepo = MomentRepository(context: context)
        let grouped = momentsRepo.daysWithMoments(in: meeting)
        let momentCount = grouped.reduce(0) { $0 + $1.moments.count }
        let cover = grouped.first?.moments.first.flatMap { momentsRepo.photosSorted($0).first?.thumbnailData }

        return ZStack(alignment: .bottomLeading) {
            if let cover, let ui = UIImage(data: cover) {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.image)
                            .fill(LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                                 startPoint: .center, endPoint: .bottom))
                    )
                    .dsPhotoShadow()
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.image)
                    .fill(DS.parchment)
                    .frame(height: 120)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("第 \(meeting.index) 次见面")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(cover != nil ? DS.onDarkMuted : DS.inkMuted)
                Text("\(meeting.city ?? "") · \(dateRange(meeting)) · \(momentCount) 条记忆")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(cover != nil ? .white : DS.ink)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 3: MainShell 接线（Modify）**

`App/MainShell.swift` 中 `case .footprints:` 改为 `case .footprints: NavigationStack { MeetingsView() }`。

- [ ] **Step 4: 构建验证并提交（第一段）**

Run: `./scripts/gen.sh && ./scripts/build.sh` → `✅ 构建通过`

```bash
git add Features/Meetings App/MainShell.swift
git commit -m "添加见面列表与计划见面表单并接入足迹页"
```

- [ ] **Step 5（回接步骤，在 T11 与 T13 完成后执行）: 卡片加跳转**

`Features/Meetings/MeetingsView.swift` 的 `card(for:)` 三个分支分别包上 NavigationLink：

```swift
        case .planned:
            NavigationLink { PlanView(meeting: meeting) } label: { plannedCard(meeting) }
                .buttonStyle(DSPressEffect())
        case .ongoing:
            NavigationLink { MeetingDetailView(meeting: meeting) } label: { ongoingCard(meeting) }
                .buttonStyle(DSPressEffect())
        case .finished:
            NavigationLink { MeetingDetailView(meeting: meeting) } label: { finishedCard(meeting) }
                .buttonStyle(DSPressEffect())
```

Run: `./scripts/gen.sh && ./scripts/build.sh` → `✅ 构建通过`

```bash
git add Features/Meetings/MeetingsView.swift
git commit -m "接通见面卡片到计划页与详情页的跳转"
```

---

### Task 11: 行前计划页

**Files:**
- Create: `Features/Plan/PlanView.swift`、`Features/Plan/PlanItemFormSheet.swift`

**Interfaces:**
- Consumes: T5 仓库、T2 `start(_:at:)`、T1 `creatorID`、`Fmt`
- Produces: `PlanView(meeting:)`（planned 状态时含「开始见面」按钮）；`PlanItemFormSheet(meeting:item:)`（item==nil 新建，否则编辑）

- [ ] **Step 1: 写 PlanItemFormSheet.swift**

```swift
import SwiftUI

struct PlanItemFormSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let meeting: CDMeeting
    let item: CDPlanItem?

    @State private var title = ""
    @State private var note = ""
    @State private var placeText = ""
    @State private var hasDay = false
    @State private var day = Date()
    @State private var hasTime = false
    @State private var time = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.md) {
                    GroupedSection {
                        HStack {
                            Text("事项").dsBody()
                            TextField("如 G102 高铁", text: $title).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        Toggle("指定日期", isOn: $hasDay.animation())
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        if hasDay {
                            DatePicker("日期", selection: $day, displayedComponents: .date)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                            DS.hairline.frame(height: 1).padding(.leading, 14)
                            Toggle("指定时间", isOn: $hasTime.animation())
                                .padding(.horizontal, 14).padding(.vertical, 8)
                            if hasTime {
                                DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                            }
                        }
                    }
                    GroupedSection {
                        HStack {
                            Text("备注").dsBody()
                            TextField("可选", text: $note).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        HStack {
                            Text("地点").dsBody()
                            TextField("可选，如 湖滨路店", text: $placeText).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                    }
                    if let item {
                        Button("删除此项") {
                            try? PlanItemRepository(context: context).delete(item)
                            dismiss()
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(DS.dsRed)
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle(item == nil ? "添加日程" : "编辑日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadIfEditing() }
        }
    }

    private func loadIfEditing() {
        guard let item else { return }
        title = item.title ?? ""
        note = item.note ?? ""
        placeText = item.placeText ?? ""
        if let d = item.day { hasDay = true; day = d }
        if let t = item.time { hasTime = true; time = t }
    }

    private func save() {
        let repo = PlanItemRepository(context: context)
        let dayValue = hasDay ? day : nil
        let timeValue = (hasDay && hasTime) ? time : nil
        let noteValue = note.isEmpty ? nil : note
        let placeValue = placeText.isEmpty ? nil : placeText
        if let item {
            try? repo.update(item, day: dayValue, time: timeValue, title: title,
                             note: noteValue, placeText: placeValue)
        } else {
            let couples = CoupleRepository(context: context)
            let authorID = (try? couples.fetchCouple()).flatMap { couples.creatorID(of: $0) }
            _ = try? repo.add(to: meeting, day: dayValue, time: timeValue, title: title,
                              note: noteValue, placeText: placeValue, authorID: authorID)
        }
        dismiss()
    }
}
```

- [ ] **Step 2: 写 PlanView.swift**

```swift
import SwiftUI
import CoreData

struct PlanView: View {
    @Environment(\.managedObjectContext) private var context
    let meeting: CDMeeting
    @FetchRequest private var items: FetchedResults<CDPlanItem>
    @State private var editingItem: CDPlanItem?
    @State private var showAdd = false

    init(meeting: CDMeeting) {
        self.meeting = meeting
        _items = FetchRequest(sortDescriptors: [],
                              predicate: NSPredicate(format: "meeting == %@", meeting))
    }

    var body: some View {
        let repo = PlanItemRepository(context: context)
        let sections = repo.sections(for: meeting, calendar: .current)
        let stats = repo.stats(for: meeting)

        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                header

                ForEach(sections.dated, id: \.day) { section in
                    Text(Fmt.monthDayWeek.string(from: section.day)).dsSectionTitle()
                    GroupedSection {
                        ForEach(Array(section.items.enumerated()), id: \.element.objectID) { i, item in
                            planRow(item, showsDivider: i < section.items.count - 1)
                        }
                    }
                }

                if !sections.undated.isEmpty {
                    Text("备忘").dsSectionTitle()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], alignment: .leading, spacing: 8) {
                        ForEach(sections.undated, id: \.objectID) { item in
                            memoChip(item)
                        }
                    }
                }

                if stats.planned == 0 {
                    Text("还没有安排，点下面「添加日程」开始").dsCaption()
                        .frame(maxWidth: .infinity).padding(.top, 24)
                }
            }
            .padding(DS.Spacing.md)
            .padding(.bottom, 80)
        }
        .background(DS.canvas)
        .navigationTitle("行前计划")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            FrostedBottomBar {
                HStack {
                    Text("已安排 \(stats.planned) 项 · 完成 \(stats.done) 项").dsCaption()
                    Spacer()
                    Button("添加日程") { showAdd = true }
                        .buttonStyle(BluePillButtonStyle())
                }
            }
        }
        .sheet(isPresented: $showAdd) { PlanItemFormSheet(meeting: meeting, item: nil) }
        .sheet(item: $editingItem) { PlanItemFormSheet(meeting: meeting, item: $0) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text([meeting.city, meeting.title].compactMap { $0 }.joined(separator: " · ")
                 .isEmpty ? "第 \(meeting.index) 次见面" : [meeting.city, meeting.title].compactMap { $0 }.joined(separator: " · "))
                .dsPageTitle()
            if let start = meeting.plannedStart {
                let days = HomeLogic.countdownDays(to: start, from: Date(), calendar: .current)
                Text("距出发还有 \(days) 天").dsCaption()
            }
            if meeting.statusRaw == MeetingStatus.planned.rawValue {
                Button("开始见面") {
                    try? MeetingRepository(context: context).start(meeting, at: Date())
                }
                .buttonStyle(BluePillButtonStyle())
                .padding(.top, 6)
            }
        }
    }

    private func planRow(_ item: CDPlanItem, showsDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    try? PlanItemRepository(context: context).toggleDone(item)
                } label: {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(item.isDone ? DS.actionBlue : DS.chipBorder)
                }
                .buttonStyle(DSPressEffect())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.time.map { Fmt.hm.string(from: $0) } ?? "全天")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.actionBlue)
                        Text(item.title ?? "").dsBody()
                            .strikethrough(item.isDone, color: DS.inkMuted)
                    }
                    if let note = item.note, !note.isEmpty {
                        Text(note).dsFootnote()
                    }
                    if let place = item.placeText, !place.isEmpty {
                        Text(place).font(.system(size: 12)).foregroundStyle(DS.actionBlue)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { editingItem = item }
            if showsDivider {
                DS.hairline.frame(height: 1).padding(.leading, 14)
            }
        }
    }

    private func memoChip(_ item: CDPlanItem) -> some View {
        Button {
            try? PlanItemRepository(context: context).toggleDone(item)
        } label: {
            Text(item.title ?? "")
                .font(.system(size: 13))
                .strikethrough(item.isDone, color: DS.inkMuted)
                .foregroundStyle(item.isDone ? DS.inkMuted : DS.ink)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(Capsule().fill(DS.canvas))
                .overlay(Capsule().stroke(DS.hairline, lineWidth: 1))
        }
        .buttonStyle(DSPressEffect())
        .contextMenu {
            Button("编辑") { editingItem = item }
            Button("删除", role: .destructive) {
                try? PlanItemRepository(context: context).delete(item)
            }
        }
    }
}
```

- [ ] **Step 3: 构建验证**

Run: `./scripts/gen.sh && ./scripts/build.sh` → `✅ 构建通过`

- [ ] **Step 4: Commit**

```bash
git add Features/Plan
git commit -m "添加行前计划页（分组清单/备忘胶囊/毛玻璃统计栏/开始见面）"
```

---

### Task 13: 见面详情·时间线与封盘（按执行顺序在 T11 之后）

**Files:**
- Create: `Features/Meetings/MeetingDetailView.swift`、`Features/Meetings/TimelineListView.swift`、`Features/Meetings/SealSheet.swift`
- Modify: `App/MainShell.swift`（`.seal` sheet 接 SealSheet）

**Interfaces:**
- Consumes: T2/T3/T4 仓库、T11 `PlanView`、`Fmt`、`StarsView`
- Produces: `MeetingDetailView(meeting:)`（chips 切换 时间线/计划；toolbar 结束见面）；`TimelineListView(meeting:)`；`SealSheet(meeting:)`。`MomentDetailView` 由 T14 提供——时间线卡片的 NavigationLink 在 T14 的 Modify 步骤中回接，本任务卡片先不带跳转。

- [ ] **Step 1: 写 SealSheet.swift**

```swift
import SwiftUI

struct SealSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let meeting: CDMeeting
    @State private var sealTime = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("封盘").dsSectionTitle()
            Text("今天到此为止，晚安。").dsCaption()
            DatePicker("封盘时刻", selection: $sealTime)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment))
            Button("确认封盘") {
                try? MeetingRepository(context: context).sealOpenDay(in: meeting, at: sealTime)
                dismiss()
            }
            .buttonStyle(BluePillButtonStyle(fullWidth: true))
        }
        .padding(DS.Spacing.md)
        .presentationDetents([.height(280)])
        .presentationCornerRadius(20)
        .presentationDragIndicator(.visible)
    }
}
```

- [ ] **Step 2: 写 TimelineListView.swift**

```swift
import SwiftUI
import CoreData

struct TimelineListView: View {
    @Environment(\.managedObjectContext) private var context
    let meeting: CDMeeting
    @FetchRequest private var momentsFetch: FetchedResults<CDMoment>
    @State private var showSeal = false

    init(meeting: CDMeeting) {
        self.meeting = meeting
        _momentsFetch = FetchRequest(sortDescriptors: [],
                                     predicate: NSPredicate(format: "dateDay.meeting == %@", meeting))
    }

    var body: some View {
        let momentsRepo = MomentRepository(context: context)
        let grouped = momentsRepo.daysWithMoments(in: meeting)

        LazyVStack(alignment: .leading, spacing: DS.Spacing.md) {
            if grouped.isEmpty {
                Text("还没有记录 · 点底栏 ⊕ 记下第一条")
                    .dsCaption()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            }
            ForEach(grouped, id: \.day.objectID) { day, moments in
                daySection(day: day, moments: moments, repo: momentsRepo)
            }
        }
        .sheet(isPresented: $showSeal) { SealSheet(meeting: meeting) }
    }

    @ViewBuilder
    private func daySection(day: CDDateDay, moments: [CDMoment], repo: MomentRepository) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("第 \(day.dayIndex) 天").dsPageTitle()
            if let opened = day.openedAt {
                Text("\(Fmt.monthDayWeek.string(from: opened)) · \(Fmt.hm.string(from: opened)) 出门").dsFootnote()
            }
        }
        ForEach(moments, id: \.objectID) { moment in
            momentCard(moment, repo: repo)
        }
        if let closed = day.closedAt {
            DarkCard {
                HStack {
                    Text("\(Fmt.hm.string(from: closed)) 封盘 · 晚安")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(moments.count) 条记忆")
                        .font(.system(size: 12)).foregroundStyle(DS.onDarkMuted)
                }
            }
        } else if meeting.statusRaw == MeetingStatus.ongoing.rawValue {
            Button("封盘") { showSeal = true }
                .buttonStyle(BluePillButtonStyle(fullWidth: true))
        }
    }

    private func momentCard(_ moment: CDMoment, repo: MomentRepository) -> some View {
        let couples = CoupleRepository(context: context)
        let partners = (try? couples.fetchCouple()).map { couples.partners(of: $0) } ?? []
        let myEval = partners.first.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let partnerName = partners.count > 1 ? (partners[1].name ?? "TA") : "TA"
        let thumb = repo.photosSorted(moment).first?.thumbnailData

        return VStack(alignment: .leading, spacing: 6) {
            if let thumb, let ui = UIImage(data: thumb) {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                    .dsPhotoShadow()
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
                Text("\(partnerName) · 还没写").dsFootnote()
            }
        }
        .padding(.bottom, 4)
    }
}
```

- [ ] **Step 3: 写 MeetingDetailView.swift**

```swift
import SwiftUI

struct MeetingDetailView: View {
    @Environment(\.managedObjectContext) private var context
    let meeting: CDMeeting
    @State private var segment = 0
    @State private var confirmEnd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("第 \(meeting.index) 次见面\(meeting.city.map { " · \($0)" } ?? "")").dsFootnote()
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        SelectableChip(title: "时间线", isSelected: segment == 0) { segment = 0 }
                        SelectableChip(title: "计划", isSelected: segment == 1) { segment = 1 }
                    }
                }

                if segment == 0 {
                    TimelineListView(meeting: meeting)
                } else {
                    PlanView(meeting: meeting)
                        .frame(minHeight: 400)
                }
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .navigationTitle(meeting.title ?? meeting.city ?? "见面")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if meeting.statusRaw == MeetingStatus.ongoing.rawValue {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("结束见面") { confirmEnd = true }
                        .font(.system(size: 14))
                }
            }
        }
        .confirmationDialog("结束这次见面？未封盘的天会一并封盘。",
                            isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("结束见面", role: .destructive) {
                try? MeetingRepository(context: context).end(meeting, at: Date())
            }
        }
    }
}
```

注意：`PlanView` 自带 navigationTitle 与底部 safeAreaInset；嵌入 segment==1 时这两者由外层导航接管，行为可接受（P6 打磨再统一）。若构建或运行发现 PlanView 嵌套 ScrollView 冲突，改为 `segment == 1` 时直接 `PlanView(meeting: meeting)` 不包 ScrollView：把外层 `ScrollView` 挪到 `segment == 0` 分支内包住时间线（实现者可按此调整并在报告注明）。

- [ ] **Step 4: MainShell 接线（Modify）**

T13 是第一个接线动作 sheet 的任务，需把 T7 留下的合并 case **拆成三个分支**。`App/MainShell.swift` 中 `.sheet(item: $activeSheet)` 的整个 switch 替换为：

```swift
            switch sheet {
            case .newMoment:
                Text("记忆表单 · T12 接线").dsCaption().padding()
            case .mood:
                Text("心情打卡 · T9 接线").dsCaption().padding()
            case .seal(let meeting):
                SealSheet(meeting: meeting)
            }
```

（T9 之后替换 `.mood` 分支、T12 之后替换 `.newMoment` 分支，各自任务里有确切代码。）

- [ ] **Step 5: 构建验证 + 执行 T10 的 Step 5 回接**

Run: `./scripts/gen.sh && ./scripts/build.sh` → `✅ 构建通过`
然后按 T10 Step 5 的内容给见面卡片加 NavigationLink 并提交（两个 commit 分开）。

- [ ] **Step 6: Commit**

```bash
git add Features/Meetings App/MainShell.swift
git commit -m "添加见面详情时间线与封盘（晚安卡/结束见面）"
```

---

### Task 12: 新建记忆表单（照片/定位/补封拦截）

**Files:**
- Create: `Features/Moments/MomentFormView.swift`、`Features/Moments/StaleSealSheet.swift`
- Create: `Support/LocationFetcher.swift`
- Modify: `project.yml`（Anniversary target settings.base 追加 `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: 用于给记忆自动记录当前位置`）
- Modify: `App/MainShell.swift`（`.newMoment` sheet 接 MomentFormView）

**Interfaces:**
- Consumes: T3 `staleOpenDay/sealOpenDay`、T4 `create/update`、T1 `creatorID`、`EmojiPickerRow/StarInputView`
- Produces: `MomentFormMode { create(CDMeeting), edit(CDMoment) }`；`MomentFormView(mode:)`；`StaleSealSheet(day:onConfirm:)`；`LocationFetcher`（`fetch() async throws -> (name: String, latitude: Double, longitude: Double)`）

- [ ] **Step 1: 写 LocationFetcher.swift**

```swift
import CoreLocation

final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    func fetch() async throws -> (name: String, latitude: Double, longitude: Double) {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        let location = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CLLocation, Error>) in
            continuation = cont
            manager.requestLocation()
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = [placemark?.name, placemark?.locality]
            .compactMap { $0 }
            .joined(separator: " · ")
        return (name.isEmpty ? "已记录坐标" : name,
                location.coordinate.latitude, location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.first {
            continuation?.resume(returning: loc)
            continuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
```

- [ ] **Step 2: 写 StaleSealSheet.swift**

```swift
import SwiftUI

struct StaleSealSheet: View {
    @Environment(\.dismiss) private var dismiss
    let day: CDDateDay
    let onConfirm: (Date) -> Void
    @State private var sealTime = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("昨天忘了封盘？").dsSectionTitle()
            Text("第 \(day.dayIndex) 天还开着。先补个封盘时刻，这条新记录会归入新的一天。").dsCaption()
            DatePicker("封盘时刻", selection: $sealTime)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment))
            Button("补封并继续") {
                onConfirm(sealTime)
                dismiss()
            }
            .buttonStyle(BluePillButtonStyle(fullWidth: true))
        }
        .padding(DS.Spacing.md)
        .presentationDetents([.height(300)])
        .presentationCornerRadius(20)
        .presentationDragIndicator(.visible)
    }
}
```

- [ ] **Step 3: 写 MomentFormView.swift**

```swift
import SwiftUI
import PhotosUI

enum MomentFormMode {
    case create(CDMeeting)
    case edit(CDMoment)
}

struct MomentFormView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let mode: MomentFormMode

    @State private var type: MomentType = .restaurant
    @State private var title = ""
    @State private var bodyText = ""
    @State private var happenedAt = Date()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photoDatas: [Data] = []
    @State private var stars = 0
    @State private var moodEmoji: String?
    @State private var comment = ""
    @State private var locationName = ""
    @State private var coords: (Double, Double)?
    @State private var locating = false
    @State private var staleDay: CDDateDay?

    private var isEdit: Bool { if case .edit = mode { true } else { false } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    typeChips
                    if !isEdit { photoSection }
                    fieldsSection
                    if !isEdit { evaluationSection; locationSection }
                    if isEdit { Text("照片、评价与地点暂不支持修改").dsFootnote() }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle(isEdit ? "编辑记忆" : "新的记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("存储") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadIfEditing() }
            .onChange(of: pickerItems) { _, items in
                Task {
                    var datas: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            datas.append(data)
                        }
                    }
                    photoDatas = datas
                }
            }
            .sheet(item: $staleDay) { day in
                StaleSealSheet(day: day) { sealTime in
                    if case let .create(meeting) = mode {
                        try? MeetingRepository(context: context).sealOpenDay(in: meeting, at: sealTime)
                        doCreate(in: meeting)
                    }
                }
            }
        }
    }

    private var typeChips: some View {
        HStack(spacing: 6) {
            ForEach(MomentType.allCases, id: \.rawValue) { t in
                SelectableChip(title: t.title, isSelected: type == t) { type = t }
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 9, matching: .images) {
                Text(photoDatas.isEmpty ? "选择照片" : "已选 \(photoDatas.count) 张")
                    .font(.system(size: 15))
                    .foregroundStyle(DS.actionBlue)
            }
            if !photoDatas.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photoDatas.enumerated()), id: \.offset) { _, data in
                            if let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable().scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
    }

    private var fieldsSection: some View {
        GroupedSection {
            HStack {
                Text("标题").dsBody()
                TextField("如 蟹家大院", text: $title).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            DS.hairline.frame(height: 1).padding(.leading, 14)
            DatePicker("时刻", selection: $happenedAt)
                .padding(.horizontal, 14).padding(.vertical, 6)
            DS.hairline.frame(height: 1).padding(.leading, 14)
            VStack(alignment: .leading, spacing: 4) {
                Text("正文 · 共同记事（可选）").dsFootnote()
                TextField("发生了什么…", text: $bodyText, axis: .vertical)
                    .lineLimit(3...6)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }

    private var evaluationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("你的评价").dsFootnote()
            StarInputView(stars: $stars)
            EmojiPickerRow(selection: $moodEmoji)
            TextField("短评：一句话点评（可选）", text: $comment)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: DS.Radius.image).fill(DS.parchment))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
    }

    private var locationSection: some View {
        GroupedSection {
            HStack {
                Text("地点").dsBody()
                TextField("可选", text: $locationName).multilineTextAlignment(.trailing)
                Button(locating ? "定位中" : "定位") {
                    locating = true
                    Task {
                        if let result = try? await LocationFetcher().fetch() {
                            locationName = result.name
                            coords = (result.latitude, result.longitude)
                        }
                        locating = false
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(DS.actionBlue)
                .disabled(locating)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }

    private func loadIfEditing() {
        guard case let .edit(moment) = mode else { return }
        type = MomentType(rawValue: moment.typeRaw) ?? .other
        title = moment.title ?? ""
        bodyText = moment.body ?? ""
        happenedAt = moment.happenedAt ?? Date()
    }

    private func save() {
        switch mode {
        case let .edit(moment):
            try? MomentRepository(context: context).update(
                moment, type: type, title: title,
                body: bodyText.isEmpty ? nil : bodyText, happenedAt: happenedAt)
            dismiss()
        case let .create(meeting):
            let stale = (try? MeetingRepository(context: context).staleOpenDay(in: meeting, now: Date())) ?? nil
            if let stale {
                staleDay = stale
                return
            }
            doCreate(in: meeting)
        }
    }

    private func doCreate(in meeting: CDMeeting) {
        let couples = CoupleRepository(context: context)
        let couple = try? couples.fetchCouple()
        let authorID = couple.flatMap { couples.creatorID(of: $0) }

        var place: CDPlace?
        if !locationName.trimmingCharacters(in: .whitespaces).isEmpty, let couple {
            let p = CDPlace(context: context)
            p.id = UUID()
            p.name = locationName
            p.latitude = coords?.0 ?? 0
            p.longitude = coords?.1 ?? 0
            p.createdAt = Date()
            p.couple = couple
            place = p
        }

        let evaluation = stars > 0 || moodEmoji != nil || !comment.isEmpty
            ? NewEvaluation(stars: Int16(stars), moodEmoji: moodEmoji,
                            comment: comment.isEmpty ? nil : comment)
            : nil

        _ = try? MomentRepository(context: context).create(
            in: meeting, type: type, title: title,
            body: bodyText.isEmpty ? nil : bodyText,
            happenedAt: happenedAt, photoDatas: photoDatas,
            myEvaluation: evaluation, authorID: authorID, place: place)
        dismiss()
    }
}

extension CDDateDay: Identifiable {}
```

- [ ] **Step 4: project.yml 加定位权限文案 + MainShell 接线**

`project.yml` Anniversary target `settings.base` 追加：
`INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: 用于给记忆自动记录当前位置`

`App/MainShell.swift` `.sheet(item:)` 的 `case .newMoment(let meeting):` 分支改为 `MomentFormView(mode: .create(meeting))`。

- [ ] **Step 5: 构建验证**

Run: `./scripts/gen.sh && ./scripts/build.sh` → `✅ 构建通过`

- [ ] **Step 6: Commit**

```bash
git add Features/Moments Support/LocationFetcher.swift project.yml App/MainShell.swift
git commit -m "添加新建记忆表单（照片导入/一键定位/补封拦截）"
```

---

### Task 14: 记忆详情与照片查看器

**Files:**
- Create: `Features/Moments/MomentDetailView.swift`、`Features/Moments/PhotoViewerView.swift`
- Modify: `Features/Meetings/TimelineListView.swift`（moment 卡包 NavigationLink → MomentDetailView）

**Interfaces:**
- Consumes: T4 仓库、T3 `daysSorted`、T12 `MomentFormView(.edit)`、`StarsView/Fmt`
- Produces: `MomentDetailView(moment:)`；`PhotoViewerView(photos:startIndex:)`

- [ ] **Step 1: 写 PhotoViewerView.swift**

```swift
import SwiftUI

struct PhotoViewerView: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [CDPhoto]
    @State var index: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.objectID) { i, photo in
                    Group {
                        if let data = photo.imageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui).resizable().scaledToFit()
                        } else {
                            Color.black
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(hex: 0xD2D2D7).opacity(0.64)))
            }
            .padding(DS.Spacing.md)
        }
        .overlay(alignment: .bottom) {
            Text("\(index + 1) / \(photos.count)")
                .font(.system(size: 13)).foregroundStyle(.white)
                .padding(.bottom, DS.Spacing.md)
        }
    }
}
```

- [ ] **Step 2: 写 MomentDetailView.swift**

```swift
import SwiftUI

struct MomentDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let moment: CDMoment
    @State private var viewerIndex: Int?
    @State private var showEdit = false
    @State private var confirmDelete = false

    var body: some View {
        let repo = MomentRepository(context: context)
        let photos = repo.photosSorted(moment)
        let couples = CoupleRepository(context: context)
        let partners = (try? couples.fetchCouple()).map { couples.partners(of: $0) } ?? []
        let myEval = partners.first.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let partnerName = partners.count > 1 ? (partners[1].name ?? "TA") : "TA"

        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if !photos.isEmpty {
                    TabView {
                        ForEach(Array(photos.enumerated()), id: \.element.objectID) { i, photo in
                            if let thumb = photo.thumbnailData ?? photo.imageData,
                               let ui = UIImage(data: thumb) {
                                Image(uiImage: ui)
                                    .resizable().scaledToFill()
                                    .onTapGesture { viewerIndex = i }
                            }
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                    .dsPhotoShadow()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\((MomentType(rawValue: moment.typeRaw) ?? .other).title) · 第 \(moment.dateDay?.dayIndex ?? 0) 天 · \(moment.happenedAt.map { Fmt.hm.string(from: $0) } ?? "")")
                        .dsFootnote()
                    Text(moment.title ?? "").dsPageTitle()
                    if let place = moment.place?.name {
                        Text(place).font(.system(size: 13)).foregroundStyle(DS.actionBlue)
                    }
                }

                ParchmentCard {
                    VStack(alignment: .leading, spacing: 8) {
                        if let myEval {
                            HStack(spacing: 6) {
                                Text("你").dsCaption()
                                StarsView(stars: Int(myEval.stars))
                                if let emoji = myEval.moodEmoji { Text(emoji) }
                            }
                            if let comment = myEval.comment {
                                Text("“\(comment)”").dsBody()
                            }
                        } else {
                            Text("你还没写评价").dsCaption()
                        }
                        DS.hairline.frame(height: 1)
                        Text("\(partnerName) · 还没写（P2 同步后她可以补上）").dsFootnote()
                    }
                }

                if let body = moment.body, !body.isEmpty {
                    Text(body).dsBody()
                }
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .navigationTitle("记忆")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑") { showEdit = true }
                    moveMenu
                    Button("删除", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(item: $viewerIndex) { i in
            PhotoViewerView(photos: photos, index: i)
        }
        .sheet(isPresented: $showEdit) { MomentFormView(mode: .edit(moment)) }
        .confirmationDialog("删除这条记忆？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                try? MomentRepository(context: context).delete(moment)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var moveMenu: some View {
        if let meeting = moment.dateDay?.meeting,
           let days = try? MeetingRepository(context: context).daysSorted(in: meeting),
           days.count > 1 {
            Menu("移到别的约会日") {
                ForEach(days, id: \.objectID) { day in
                    if day.objectID != moment.dateDay?.objectID {
                        Button("第 \(day.dayIndex) 天") {
                            try? MomentRepository(context: context).move(moment, to: day)
                        }
                    }
                }
            }
        }
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
```

（`extension Int: Identifiable` 仅为 `fullScreenCover(item:)` 服务；若审查认为污染标准类型，可改为包一层 `struct ViewerIndex: Identifiable { let id: Int }`——实现者可直接采用包装结构并在报告注明，两种写法都符合本计划。）

- [ ] **Step 3: TimelineListView 回接跳转（Modify）**

`Features/Meetings/TimelineListView.swift` 的 `momentCard(_:repo:)` 调用处（`ForEach(moments...)` 内）包上：

```swift
                NavigationLink {
                    MomentDetailView(moment: moment)
                } label: {
                    momentCard(moment, repo: repo)
                }
                .buttonStyle(.plain)
```

- [ ] **Step 4: 构建验证**

Run: `./scripts/gen.sh && ./scripts/build.sh` → `✅ 构建通过`

- [ ] **Step 5: Commit**

```bash
git add Features/Moments Features/Meetings/TimelineListView.swift
git commit -m "添加记忆详情与照片查看器并接通时间线跳转"
```

---

### Task 15: 设置最小集

**Files:**
- Create: `Features/Settings/SettingsView.swift`
- Modify: `Features/Home/HomeView.swift`（header 加 gear NavigationLink）

**Interfaces:**
- Consumes: T1 仓库、`@AppStorage("showCountdown")`
- Produces: `SettingsView`

- [ ] **Step 1: 写 SettingsView.swift**

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @AppStorage("showCountdown") private var showCountdown = true
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @State private var myName = ""
    @State private var partnerName = ""
    @State private var anniversary = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("我们的资料").dsSectionTitle()
                GroupedSection {
                    HStack {
                        Text("我的昵称").dsBody()
                        TextField("", text: $myName).multilineTextAlignment(.trailing)
                            .onSubmit(save)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    DS.hairline.frame(height: 1).padding(.leading, 14)
                    HStack {
                        Text("TA 的昵称").dsBody()
                        TextField("", text: $partnerName).multilineTextAlignment(.trailing)
                            .onSubmit(save)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    DS.hairline.frame(height: 1).padding(.leading, 14)
                    DatePicker("在一起的日子", selection: $anniversary,
                               in: ...Date(), displayedComponents: .date)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .onChange(of: anniversary) { _, newValue in
                            couples.first?.anniversaryDate = newValue
                            try? context.save()
                        }
                }

                Text("显示").dsSectionTitle()
                GroupedSection {
                    Toggle("首页倒计时", isOn: $showCountdown)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                }

                Text("配对与同步在 P2 阶段开启 · 版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .dsFootnote()
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.parchment)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onDisappear(perform: save)
    }

    private func load() {
        guard let couple = couples.first else { return }
        let partners = CoupleRepository(context: context).partners(of: couple)
        myName = partners.first?.name ?? ""
        partnerName = partners.count > 1 ? (partners[1].name ?? "") : ""
        anniversary = couple.anniversaryDate ?? Date()
    }

    private func save() {
        guard let couple = couples.first else { return }
        let partners = CoupleRepository(context: context).partners(of: couple)
        if !myName.trimmingCharacters(in: .whitespaces).isEmpty {
            partners.first?.name = myName
        }
        if partners.count > 1, !partnerName.trimmingCharacters(in: .whitespaces).isEmpty {
            partners[1].name = partnerName
        }
        try? context.save()
    }
}
```

- [ ] **Step 2: HomeView 加 gear（Modify）**

`Features/Home/HomeView.swift` 的 `header(_:)` 中 `Spacer()` 之后追加：

```swift
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.inkMuted)
            }
```

- [ ] **Step 3: 构建验证**

Run: `./scripts/gen.sh && ./scripts/build.sh` → `✅ 构建通过`

- [ ] **Step 4: Commit**

```bash
git add Features/Settings Features/Home/HomeView.swift
git commit -m "添加设置最小集（资料/纪念日/倒计时开关）"
```

---

### Task 16: 预览数据扩充、回归与 P1 验收

**Files:**
- Modify: `Support/PreviewData.swift`（do 块末尾、`try ctx.save()` 之前追加）
- Modify: `README.md`

**Interfaces:**
- Consumes: 全部前序产物
- Produces: 含计划中见面/计划项/心情的完整预览栈；README P1 状态

- [ ] **Step 1: PreviewData 追加样例（在 `try ctx.save()` 之前插入）**

```swift
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
```

（注意保留原有第 7 次见面样例；`plan` 旧样例变量与新代码无命名冲突。）

- [ ] **Step 2: README 更新**

`README.md` 「阶段」段落替换为：

```markdown
## 阶段

P0 地基 ✅ → **P1 记忆核心 ✅（当前）** → P2 双人同步 → P3 视图 → P4 小本本 → P5 她 → P6 打磨。
各阶段实现计划在 `docs/superpowers/plans/`。

P1 已可单机使用：创建空间 → 计划见面 → 开始见面 → ⊕ 记录记忆（照片/评价/定位）→ 封盘 → 时间线回看 → 行前计划勾选 → 每日心情。
```

- [ ] **Step 3: 全量回归**

Run: `./scripts/gen.sh && ./scripts/test.sh`
Expected: `✅ 测试通过`（P0 18 例 + P1 新增 ≥14 例）

- [ ] **Step 4: 模拟器人工验收（控制器/用户执行）**

`./scripts/run.sh` 后按序检查：① 引导页创建空间 → ② 首页大字/倒计时空状态 → ③ 足迹·计划见面（填日期）→ ④ 首页出现倒计时卡 → ⑤ 计划页添加 2 个日程（1 个无日期）排序正确 → ⑥ 开始见面 → ⑦ ⊕ 记忆（带照片+评分+短评）→ ⑧ 时间线出现第 1 天与卡片 → ⑨ 封盘出现晚安卡 → ⑩ 再记一条自动开第 2 天 → ⑪ 心情打卡后首页显示 emoji → ⑫ 设置改昵称生效。

- [ ] **Step 5: Commit（P1 完成）**

```bash
git add Support/PreviewData.swift README.md
git commit -m "扩充预览数据并更新 README，P1 记忆核心完成"
```

---

## 执行顺序（控制器派发依据）

**T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T10（Step 1-4）→ T11 → T13 → T10（Step 5 回接）→ T9 → T12 → T14 → T15 → T16**

## P1 验收清单

- `./scripts/test.sh` 全绿（P0 18 例 + P1 逻辑层新增：roleIndex 2、Meeting 4、DateDay 5、Thumbnailer 2、Moment 3、PlanItem 3、HomeLogic 3、DailyMood 1 ≈ 41 例）
- 模拟器人工验收 12 步全过（T16 Step 4）
- 时间线正确展示跨午夜归属（第 1 天含凌晨记录直至封盘）
- 无第三方依赖；深色内容均为圆角卡片；按钮文案 ≤6 字无 emoji
- `git log` 小步提交与任务对应

