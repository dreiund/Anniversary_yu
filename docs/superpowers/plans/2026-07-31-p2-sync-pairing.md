# P2 双人化（CloudKit 同步 + CKShare 配对）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 P1 单机 App 变成两台 iPhone 实时互通的双人 App：私有库镜像上云、CKShare 一次配对、本机身份解析、对方补评、新记忆/封盘通知，并给出 TestFlight 分发与 CloudKit 生产部署手册。

**Architecture:** NSPersistentCloudKitContainer 双 store（私有库 `Anniversary.sqlite` scope=.private + 共享库 `Anniversary-shared.sqlite` scope=.shared，同一容器 `iCloud.com.fkc.anniversary`）。创建方把根对象 CDCouple 整树 `share()` 进共享 zone，对方经链接 `acceptShareInvitations` 加入后，全部数据双向自动镜像。本机身份不用旗标：couple 落在共享库文件 → 本机是受邀方（partners[1]），否则是创建方（partners[0]）——纯数据判定，可单测、重装自愈。存量 P1 数据靠 P0 起就开着的 persistent history 在首次开云时全量导出。

**Tech Stack:** SwiftUI + Core Data + NSPersistentCloudKitContainer + CloudKit（CKShare）+ UserNotifications。零第三方。

**基线：** main @ `6c7b96e`（P0+P1 已合并，43/43 测试绿）。分支 `worktree-p2-sync-pairing`。

## Global Constraints（每个任务隐含遵守）

- 部署基线 **iOS 18.0**；纯 SwiftUI；**零第三方依赖**，仅系统框架。
- 视觉纪律：唯一交互色 actionBlue `#0066CC`；深色内容一律 darkCard 圆角卡片**禁止通栏色带**；按钮文案**单行 ≤6 字、无 emoji**（既定例外仅「创建我们的空间」7 字）。UI 文案一律简体中文。
- CloudKit 建模约束不可破坏（全关系 optional+inverse、非可选属性带默认值、禁 unique/ordered constraint）——`ModelSchemaTests` 已锁死，任何模型改动必须让它保持绿。
- `partners(of:)` 的 roleIndex 保序是硬约束：`[0]`=创建者、`[1]`=受邀方，禁止改排序键。写入各类 `authorPartnerID` 一律经 `CoupleRepository.currentPartnerID(of:)`（本计划 Task 3 引入后，全工程不得再出现 `partners[0].id` 当作者的写法）。
- `CDPlace.categoryRaw` 在 P3 定义 PlaceCategory 枚举前**禁止写入**。
- `@FetchRequest` 声明必须在 body 中被读取才会注册刷新依赖；工程既有的 `let _ = xxx.count  // 注册观察…` 惯用法是**刻意为之**，不得当死代码清理；新增 FetchRequest 同样必须带观察读取。
- 云容器 ID 恒为 `iCloud.com.fkc.anniversary`；本机事务作者恒为 `"AnniversaryApp"`。这两个字符串改动会破坏历史过滤与增量导出判定，视为破坏性变更。
- 门禁：每任务收尾跑 `./scripts/test.sh` 须见 `✅ 测试通过`；涉及工程配置的任务另跑 `./scripts/build.sh` 须见 `✅ 构建通过`。测试全部用 `PersistenceController(inMemory: true)` 或临时目录 SQLite，不得依赖 iCloud 登录态或网络。
- 提交信息中文；每任务按步骤小步提交。
- 通知/横幅文案是内容不是按钮，不受 6 字限制；新按钮全表：接受邀请 / 生成邀请 / 发出邀请 / 锁定邀请 / 补上评价 / 保存 / 知道了（均 ≤6 字）。

## 文件结构总览

```
project.yml                          修改：info/entitlements 迁移 + 推送后台模式（T1）
App/Info.plist                       新增（xcodegen 生成物，入库）（T1）
App/Anniversary.entitlements         新增（T1）
App/AppDelegate.swift                新增：App/Scene delegate 桥接接受邀请（T7）
App/AnniversaryApp.swift             修改：delegate adaptor + AppServices（T7、T10）
App/MainShell.swift                  修改：onAppear 封盘提醒对账（T11）
Persistence/PersistenceController.swift  重写：双 store + 事务作者 + schema 初始化开关（T2）
Persistence/CoupleRepository.swift   修改：currentPartner 家族替换 creatorID（T3）
Persistence/DailyMoodRepository.swift 修改：重复容错的确定性查找（T5）
Persistence/SharingManager.swift     新增：CKShare 创建/读取/锁定/接受（T6）
Persistence/HistoryMonitor.swift     新增：远程导入监听 → 新记忆通知（T10）
Persistence/MomentRepository.swift   修改：upsertEvaluation（T9）
Support/LocalNotifier.swift          新增：本地通知实现（T10）
Support/SealReminder.swift           新增：23:30 封盘提醒计划器（T11）
Features/Onboarding/OnboardingView.swift 修改：接受邀请入口 + 等待态（T7）
Features/Settings/SettingsView.swift 修改：配对与同步区 + 通知开关 + currentPartner（T4、T8、T11）
Features/Home/HomeView.swift         修改：currentPartner + 待补评提醒行 + 同步暂停横幅（T4、T12）
Features/Meetings/TimelineListView.swift 修改：对方评价真实展示（T4）
Features/Moments/MomentDetailView.swift  修改：对方评价真实展示 + 补上评价（T4、T9）
Features/Moments/EvaluationFormSheet.swift 新增：补评表单（T9）
Tests/PersistenceControllerTests.swift   扩充（T2）
Tests/CurrentPartnerTests.swift      新增（T3）
Tests/DailyMoodRepositoryTests.swift 扩充（T5）
Tests/PlanItemIdentityTests.swift    新增（T5）
Tests/SharingManagerTests.swift      新增（T6）
Tests/MomentRepositoryTests.swift    扩充（T9）
Tests/HistoryMonitorTests.swift      新增（T10）
Tests/SealReminderTests.swift        新增（T11）
docs/RELEASE.md                      新增：TestFlight 与 CloudKit 生产部署手册（T13）
```

P1 挂账清账映射：① 补封拦截手测步骤 → T13 验收清单第 11 步；② 五处 `partners[0]`=我 → T3+T4；③ DailyMood upsert 原子性/时区 → T5；④ CDPlanItem Identifiable 身份 → T5（证实见证为业务 UUID 并加锁测试）；⑤ 观察声明惯用法 → 全局约束明文保护。

---

### Task 1: 云能力工程配置（entitlements + Info.plist 迁移）

**Files:**
- Modify: `project.yml`
- Create（由 `./scripts/gen.sh` 生成后入库）: `App/Info.plist`、`App/Anniversary.entitlements`

**Interfaces:**
- Consumes: 无（纯工程配置）。
- Produces: App target 具备 CloudKit/推送后台/CKSharingSupported 能力；后续所有任务的构建前提。测试 target 的 Info.plist 生成方式保持不变。

**背景：** 目前 Info.plist 靠 `GENERATE_INFOPLIST_FILE: YES` + `INFOPLIST_KEY_*` 生成，无法表达 `CKSharingSupported`、`UIBackgroundModes` 等自定义键，需迁移为 xcodegen 的 `info:` 块（xcodegen 会在 gen 时生成实体 plist 文件）。entitlements 同理用 `entitlements:` 块。**注意**：`GENERATE_INFOPLIST_FILE: YES` 必须从项目级下移到测试 target（app target 改用文件后两者并存会冲突）。

- [ ] **Step 1: 重写 project.yml**

用以下完整内容替换 `project.yml`（较现状的变化：项目级 settings 移除 `GENERATE_INFOPLIST_FILE`；app target 增 `info:`/`entitlements:` 块并移除全部 `INFOPLIST_KEY_*`；scheme 预置关闭状态的 `-InitCloudKitSchema` 启动参数；测试 target 补 `GENERATE_INFOPLIST_FILE: YES`）：

```yaml
name: Anniversary
options:
  createIntermediateGroups: true
  deploymentTarget:
    iOS: "18.0"
settings:
  base:
    SWIFT_VERSION: "5.10"
    CURRENT_PROJECT_VERSION: 1
    MARKETING_VERSION: 0.1.0
    DEVELOPMENT_TEAM: N4YSFLZ44L
    CODE_SIGN_STYLE: Automatic
targets:
  Anniversary:
    type: application
    platform: iOS
    sources:
      - App
      - Features
      - DesignSystem
      - Domain
      - Persistence
      - Support
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Anniversary
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        NSLocationWhenInUseUsageDescription: 用于给记忆自动记录当前位置
        CKSharingSupported: true
        UIBackgroundModes: [remote-notification]
        ITSAppUsesNonExemptEncryption: false
    entitlements:
      path: App/Anniversary.entitlements
      properties:
        com.apple.developer.icloud-services: [CloudKit]
        com.apple.developer.icloud-container-identifiers: [iCloud.com.fkc.anniversary]
        aps-environment: development
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.fkc.anniversary
        GENERATE_INFOPLIST_FILE: NO
        TARGETED_DEVICE_FAMILY: "1"
    scheme:
      testTargets:
        - AnniversaryTests
      commandLineArguments:
        "-InitCloudKitSchema": false
  AnniversaryTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - Tests
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: Anniversary
```

- [ ] **Step 2: 生成工程并确认两个新文件落盘**

Run: `./scripts/gen.sh && ls App/Info.plist App/Anniversary.entitlements`
Expected: `Created project …` 且两个文件存在。用 `plutil -lint App/Info.plist` 确认合法。

- [ ] **Step 3: 构建 + 全量测试**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: `✅ 构建通过` 与 `✅ 测试通过`（43 个既有测试全绿；本任务不新增测试——工程配置的验证就是这两道门禁）。若报 Info.plist 冲突/缺键，检查 Step 1 是否漏掉 `GENERATE_INFOPLIST_FILE: NO`（app）与 `YES`（tests）的分置。

- [ ] **Step 4: 提交**

```bash
git add project.yml App/Info.plist App/Anniversary.entitlements
git commit -m "P2-T1 工程云能力：iCloud 容器/CKShare/推送后台 entitlements 与 Info.plist 迁移"
```

---

### Task 2: PersistenceController 双 store 与 schema 初始化开关

**Files:**
- Modify: `Persistence/PersistenceController.swift`（整文件替换）
- Test: `Tests/PersistenceControllerTests.swift`（追加两个测试）

**Interfaces:**
- Consumes: `ModelSchema.model`（P0 既有）。
- Produces（后续任务依赖的确切签名）:
  - `static let cloudContainerID = "iCloud.com.fkc.anniversary"`
  - `static let localTransactionAuthor = "AnniversaryApp"`
  - `static let privateStoreFileName = "Anniversary.sqlite"` / `static let sharedStoreFileName = "Anniversary-shared.sqlite"`
  - `private(set) var privateStore: NSPersistentStore?` / `private(set) var sharedStore: NSPersistentStore?`
  - `static func makeStoreDescriptions(inMemory: Bool, directory: URL) -> [NSPersistentStoreDescription]`（纯函数，供单测）
  - `container: NSPersistentCloudKitContainer`（既有，不改名）

**要点：** inMemory 路径保持 P0/P1 的单 store（/dev/null、无云选项），43 个既有测试前提不变。磁盘路径变为私有+共享双 store，两者都开 history tracking 与 remote change 通知。私有库文件名沿用 `Anniversary.sqlite`——他手机上的 P1 存量数据原地开云，靠一直开着的 history 全量导出。

- [ ] **Step 1: 写失败测试（追加到 Tests/PersistenceControllerTests.swift）**

```swift
    func testDiskDescriptionsHavePrivateAndSharedScopes() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let descs = PersistenceController.makeStoreDescriptions(inMemory: false, directory: dir)
        XCTAssertEqual(descs.count, 2)
        XCTAssertEqual(descs[0].url?.lastPathComponent, "Anniversary.sqlite")
        XCTAssertEqual(descs[0].cloudKitContainerOptions?.containerIdentifier, "iCloud.com.fkc.anniversary")
        XCTAssertEqual(descs[0].cloudKitContainerOptions?.databaseScope, .private)
        XCTAssertEqual(descs[1].url?.lastPathComponent, "Anniversary-shared.sqlite")
        XCTAssertEqual(descs[1].cloudKitContainerOptions?.containerIdentifier, "iCloud.com.fkc.anniversary")
        XCTAssertEqual(descs[1].cloudKitContainerOptions?.databaseScope, .shared)
        for d in descs {
            XCTAssertEqual(d.options[NSPersistentHistoryTrackingKey] as? NSNumber, true)
            XCTAssertEqual(d.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber, true)
        }
    }

    func testInMemoryKeepsSingleLocalStoreAndAuthor() {
        let descs = PersistenceController.makeStoreDescriptions(
            inMemory: true, directory: URL(fileURLWithPath: NSTemporaryDirectory()))
        XCTAssertEqual(descs.count, 1)
        XCTAssertNil(descs[0].cloudKitContainerOptions)
        let pc = PersistenceController(inMemory: true)
        XCTAssertNotNil(pc.privateStore)
        XCTAssertNil(pc.sharedStore)
        XCTAssertEqual(pc.viewContext.transactionAuthor, "AnniversaryApp")
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL——`makeStoreDescriptions`、`privateStore` 等符号不存在（编译错误即失败形态）。

- [ ] **Step 3: 整文件替换 Persistence/PersistenceController.swift**

```swift
import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    static let cloudContainerID = "iCloud.com.fkc.anniversary"
    static let localTransactionAuthor = "AnniversaryApp"
    static let privateStoreFileName = "Anniversary.sqlite"
    static let sharedStoreFileName = "Anniversary-shared.sqlite"

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// inMemory 保持 P0/P1 的单 store（/dev/null、无云选项），既有测试前提不变；
    /// 磁盘路径为 私有+共享 双 store，文件名是身份解析的依据（CoupleRepository）。
    static func makeStoreDescriptions(inMemory: Bool, directory: URL) -> [NSPersistentStoreDescription] {
        if inMemory {
            let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            description.cloudKitContainerOptions = nil
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            return [description]
        }
        let privateDescription = NSPersistentStoreDescription(url: directory.appendingPathComponent(privateStoreFileName))
        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudContainerID)
        privateOptions.databaseScope = .private
        privateDescription.cloudKitContainerOptions = privateOptions

        let sharedDescription = NSPersistentStoreDescription(url: directory.appendingPathComponent(sharedStoreFileName))
        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudContainerID)
        sharedOptions.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = sharedOptions

        for description in [privateDescription, sharedDescription] {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        return [privateDescription, sharedDescription]
    }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Anniversary", managedObjectModel: ModelSchema.model)

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if !inMemory {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        container.persistentStoreDescriptions = Self.makeStoreDescriptions(inMemory: inMemory, directory: dir)

        var loadError: Error?
        container.loadPersistentStores { _, error in if let error { loadError = error } }
        precondition(loadError == nil, "本地库加载失败: \(String(describing: loadError))")

        let stores = container.persistentStoreCoordinator.persistentStores
        if inMemory {
            privateStore = stores.first
            sharedStore = nil
        } else {
            privateStore = stores.first { $0.url?.lastPathComponent == Self.privateStoreFileName }
            sharedStore = stores.first { $0.url?.lastPathComponent == Self.sharedStoreFileName }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        container.viewContext.transactionAuthor = Self.localTransactionAuthor

        #if DEBUG
        // 一次性动作：Xcode scheme 勾选 -InitCloudKitSchema 跑一次，把 15 个实体的
        // 记录类型全量推到 CloudKit Development 环境（含 P4/P5 未产生数据的实体），
        // 之后在 CloudKit Console 部署到 Production。见 docs/RELEASE.md。
        if ProcessInfo.processInfo.arguments.contains("-InitCloudKitSchema") {
            do {
                try container.initializeCloudKitSchema(options: [])
                print("✅ CloudKit schema 初始化完成（Development 环境）")
            } catch {
                print("❌ CloudKit schema 初始化失败：\(error)")
            }
        }
        #endif
    }
}
```

- [ ] **Step 4: 跑全量测试确认通过**

Run: `./scripts/test.sh`
Expected: `✅ 测试通过`（45 个）。注意：模拟器未登录 iCloud 时 App 运行会在控制台刷镜像错误日志，属预期噪音，不影响本地读写。

- [ ] **Step 5: 提交**

```bash
git add Persistence/PersistenceController.swift Tests/PersistenceControllerTests.swift
git commit -m "P2-T2 持久层开云：私有+共享双 store、事务作者与 schema 初始化开关"
```

---

### Task 3: 本机身份解析 currentPartner（清 P1 挂账②之基础）

**Files:**
- Modify: `Persistence/CoupleRepository.swift`
- Modify: `Features/Moments/MomentFormView.swift`、`Features/Home/MoodSheet.swift`、`Features/Plan/PlanItemFormSheet.swift`（凡调用 `creatorID(of:)` 之处——先 `grep -rn "creatorID" App Features Persistence Support Tests` 找全，逐一替换为 `currentPartnerID(of:)`；删除 `creatorID` 后编译器会兜底找漏）
- Test: `Tests/CurrentPartnerTests.swift`（新建）

**Interfaces:**
- Consumes: `PersistenceController.privateStoreFileName` / `.sharedStoreFileName`（T2）。
- Produces:
  - `CoupleRepository.isParticipantDevice(_ couple: CDCouple) -> Bool`
  - `CoupleRepository.currentPartner(of couple: CDCouple) -> CDPartner?`
  - `CoupleRepository.otherPartner(of couple: CDCouple) -> CDPartner?`
  - `CoupleRepository.currentPartnerID(of couple: CDCouple) -> UUID?`
  - `creatorID(of:)` **删除**（全工程不再存在该符号）

**判定原理（写进代码注释）：** 创建方的 couple 永远住私有库文件；受邀方的 couple 只会经共享 zone 镜像进共享库文件。看 `couple.objectID.persistentStore` 的文件名即知本机角色——无需本地旗标，删 App 重装后依然正确。

- [ ] **Step 1: 写失败测试（新建 Tests/CurrentPartnerTests.swift）**

```swift
import XCTest
import CoreData
@testable import Anniversary

final class CurrentPartnerTests: XCTestCase {
    private var tmpDir: URL!
    private var container: NSPersistentContainer!
    private var privateStore: NSPersistentStore!
    private var sharedStore: NSPersistentStore!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        container = NSPersistentContainer(name: "T", managedObjectModel: ModelSchema.model)
        let p = NSPersistentStoreDescription(url: tmpDir.appendingPathComponent(PersistenceController.privateStoreFileName))
        let s = NSPersistentStoreDescription(url: tmpDir.appendingPathComponent(PersistenceController.sharedStoreFileName))
        container.persistentStoreDescriptions = [p, s]
        var loadError: Error?
        container.loadPersistentStores { _, e in if let e { loadError = e } }
        XCTAssertNil(loadError)
        let stores = container.persistentStoreCoordinator.persistentStores
        privateStore = stores.first { $0.url?.lastPathComponent == PersistenceController.privateStoreFileName }
        sharedStore = stores.first { $0.url?.lastPathComponent == PersistenceController.sharedStoreFileName }
    }

    override func tearDownWithError() throws {
        container = nil
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func makeCouple(in store: NSPersistentStore) throws -> CDCouple {
        let context = container.viewContext
        let couple = CDCouple(context: context)
        couple.id = UUID(); couple.createdAt = Date()
        let me = CDPartner(context: context)
        me.id = UUID(); me.name = "阿铖"; me.roleIndex = 0; me.couple = couple
        let her = CDPartner(context: context)
        her.id = UUID(); her.name = "小于"; her.roleIndex = 1; her.couple = couple
        for object in [couple, me, her] as [NSManagedObject] { context.assign(object, to: store) }
        try context.save()
        return couple
    }

    func testOwnerDeviceResolvesToRoleZero() throws {
        let couple = try makeCouple(in: privateStore)
        let repo = CoupleRepository(context: container.viewContext)
        XCTAssertFalse(repo.isParticipantDevice(couple))
        XCTAssertEqual(repo.currentPartner(of: couple)?.roleIndex, 0)
        XCTAssertEqual(repo.otherPartner(of: couple)?.roleIndex, 1)
        XCTAssertEqual(repo.currentPartnerID(of: couple), repo.partners(of: couple)[0].id)
    }

    func testParticipantDeviceResolvesToRoleOne() throws {
        let couple = try makeCouple(in: sharedStore)
        let repo = CoupleRepository(context: container.viewContext)
        XCTAssertTrue(repo.isParticipantDevice(couple))
        XCTAssertEqual(repo.currentPartner(of: couple)?.roleIndex, 1)
        XCTAssertEqual(repo.otherPartner(of: couple)?.roleIndex, 0)
        XCTAssertEqual(repo.currentPartnerID(of: couple), repo.partners(of: couple)[1].id)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL——`isParticipantDevice` 等符号不存在。

- [ ] **Step 3: 实现（Persistence/CoupleRepository.swift，替换 creatorID 段）**

删除 `creatorID(of:)` 整个方法（含注释），在 `partners(of:)` 之后追加：

```swift
    /// 本机是否为受邀加入的一方：创建方的 couple 永远在私有库文件里，
    /// 受邀方的 couple 只会经共享 zone 镜像进共享库文件。
    /// 纯数据判定——无本地旗标，删 App 重装后依然正确，可脱离 CloudKit 单测。
    func isParticipantDevice(_ couple: CDCouple) -> Bool {
        couple.objectID.persistentStore?.url?.lastPathComponent == PersistenceController.sharedStoreFileName
    }

    /// 本机使用者：创建方设备 = partners[0]，受邀方设备 = partners[1]。
    /// 全工程写 authorPartnerID 的唯一来源是 currentPartnerID(of:)。
    func currentPartner(of couple: CDCouple) -> CDPartner? {
        let list = partners(of: couple)
        if isParticipantDevice(couple) {
            return list.count > 1 ? list[1] : nil
        }
        return list.first
    }

    func otherPartner(of couple: CDCouple) -> CDPartner? {
        guard let mine = currentPartner(of: couple) else { return nil }
        return partners(of: couple).first { $0.objectID != mine.objectID }
    }

    func currentPartnerID(of couple: CDCouple) -> UUID? {
        currentPartner(of: couple)?.id
    }
```

- [ ] **Step 4: 替换全部 creatorID 调用点**

Run: `grep -rn "creatorID" App Features Persistence Support Tests`
把每一处 `creatorID(of:` 改为 `currentPartnerID(of:`（语义不变：单机/创建方设备两者等价；受邀方设备从此写对作者）。跑 `./scripts/build.sh` 用编译器确认无残留。

- [ ] **Step 5: 跑全量测试确认通过**

Run: `./scripts/test.sh`
Expected: `✅ 测试通过`（47 个）。

- [ ] **Step 6: 提交**

```bash
git add Persistence/CoupleRepository.swift Tests/CurrentPartnerTests.swift Features App
git commit -m "P2-T3 本机身份解析：couple 所在 store 判定 currentPartner，废除 creatorID"
```

---

### Task 4: 视图层身份改写（清 P1 挂账②五处）+ 对方评价真实展示

**Files:**
- Modify: `Features/Home/HomeView.swift`（moodCard）
- Modify: `Features/Settings/SettingsView.swift`（load/save）
- Modify: `Features/Moments/MomentDetailView.swift`（评价区）
- Modify: `Features/Meetings/TimelineListView.swift`（momentCard 评价区）

**Interfaces:**
- Consumes: `currentPartner(of:)` / `otherPartner(of:)`（T3）；`MomentRepository.evaluation(of:by:)`（P1 既有）。
- Produces: 全部“我/TA”视图逻辑与设备无关；时间线与详情页的对方评价从占位文案变为真实数据渲染（有则显示星评+短评，无则“还没写”）。`Features/Plan/PlanView.swift` 的 `authorName` 是按 ID 查名，不属“我”假设，**不改**。

- [ ] **Step 1: HomeView.moodCard 改身份解析**

`moodCard(_:)` 内，将：

```swift
        let partners = repo.partners(of: couple)
        let moodRepo = DailyMoodRepository(context: context)
        let mine = moodRepo.mood(couple: couple, authorID: partners.first?.id, day: Date(), calendar: .current)
        let partnerMood = partners.count > 1
            ? moodRepo.mood(couple: couple, authorID: partners[1].id, day: Date(), calendar: .current)
            : nil
```

替换为：

```swift
        let me = repo.currentPartner(of: couple)
        let other = repo.otherPartner(of: couple)
        let moodRepo = DailyMoodRepository(context: context)
        let mine = moodRepo.mood(couple: couple, authorID: me?.id, day: Date(), calendar: .current)
        let partnerMood = other.flatMap {
            moodRepo.mood(couple: couple, authorID: $0.id, day: Date(), calendar: .current)
        }
```

同函数尾部 `if partners.count > 1, partnerMood == nil { Text("\(partners[1].name ?? "TA") 还没打卡")…}` 改为 `if let other, partnerMood == nil { Text("\(other.name ?? "TA") 还没打卡").dsFootnote() }`。`header(_:)` 的双头像遍历保持 `partners`（展示两人，与身份无关，不改）。

- [ ] **Step 2: SettingsView 昵称行改身份解析**

`load()` 中 `myName = partners.first?.name ?? ""`、`partnerName = partners.count > 1 ? (partners[1].name ?? "") : ""` 改为：

```swift
        let repo = CoupleRepository(context: context)
        myName = repo.currentPartner(of: couple)?.name ?? ""
        partnerName = repo.otherPartner(of: couple)?.name ?? ""
```

`save()` 中对应改为：

```swift
        let repo = CoupleRepository(context: context)
        if !myName.trimmingCharacters(in: .whitespaces).isEmpty {
            repo.currentPartner(of: couple)?.name = myName
        }
        if !partnerName.trimmingCharacters(in: .whitespaces).isEmpty {
            repo.otherPartner(of: couple)?.name = partnerName
        }
```

（两处原有的 `let partners = …` 行删除。）

- [ ] **Step 3: MomentDetailView 评价区真实双侧**

把 body 顶部的：

```swift
        let partners = (try? couples.fetchCouple()).map { couples.partners(of: $0) } ?? []
        let myEval = partners.first.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let partnerName = partners.count > 1 ? (partners[1].name ?? "TA") : "TA"
```

替换为：

```swift
        let couple = try? couples.fetchCouple()
        let me = couple.flatMap { couples.currentPartner(of: $0) }
        let other = couple.flatMap { couples.otherPartner(of: $0) }
        let myEval = me.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let otherEval = other.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let partnerName = other?.name ?? "TA"
```

评价卡 ParchmentCard 内，删除整行 `Text("\(partnerName) · 还没写（P2 同步后她可以补上）").dsFootnote()`，替换为真实渲染：

```swift
                        if let otherEval {
                            HStack(spacing: 6) {
                                Text(partnerName).dsCaption()
                                StarsView(stars: Int(otherEval.stars))
                                if let emoji = otherEval.moodEmoji { Text(emoji) }
                            }
                            if let comment = otherEval.comment, !comment.isEmpty {
                                Text("“\(comment)”").dsBody()
                            }
                        } else {
                            Text("\(partnerName) · 还没写").dsCaption()
                        }
```

- [ ] **Step 4: TimelineListView.momentCard 同步改写**

将：

```swift
        let partners = (try? couples.fetchCouple()).map { couples.partners(of: $0) } ?? []
        let myEval = partners.first.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let partnerName = partners.count > 1 ? (partners[1].name ?? "TA") : "TA"
```

替换为：

```swift
        let couple = try? couples.fetchCouple()
        let me = couple.flatMap { couples.currentPartner(of: $0) }
        let other = couple.flatMap { couples.otherPartner(of: $0) }
        let myEval = me.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let otherEval = other.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let partnerName = other?.name ?? "TA"
```

尾部评价 VStack 中 `Text("\(partnerName) · 还没写").dsFootnote()` 替换为：

```swift
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
```

- [ ] **Step 5: 构建 + 全量测试 + 预览抽查**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 两个 ✅。本任务是视图接线，无新单测；正确性由 T3 的仓库测试 + 编译 + 审查把关。

- [ ] **Step 6: 提交**

```bash
git add Features
git commit -m "P2-T4 视图层现在/对方身份改写，时间线与详情页真实渲染双侧评价"
```

---

### Task 5: P1 挂账③④清账（DailyMood 确定性 + PlanItem 身份见证锁定)

**Files:**
- Modify: `Persistence/DailyMoodRepository.swift`（`mood(couple:authorID:day:calendar:)`）
- Test: `Tests/DailyMoodRepositoryTests.swift`（追加）、`Tests/PlanItemIdentityTests.swift`（新建）

**Interfaces:**
- Consumes: 无新依赖。
- Produces: `mood(…)` 在同键重复记录下两端选取一致；`CDPlanItem` 的 `Identifiable` 见证被测试锁定为业务 UUID（若见证实为 ObjectIdentifier，此测试编译期即暴露）。

**背景：** CloudKit 禁 unique 约束，双端并发下同 (author, day) 可能短暂重复；set-scan 取 first 是无序的，两端可能各选一条造成 UI 抖动。改为按 id 字典序取首条。时区问题裁定：两位使用者均在东八区，`startOfDay` 以本机时区归一符合 spec §9，写注释存档即可。

- [ ] **Step 1: 写失败测试（追加到 Tests/DailyMoodRepositoryTests.swift）**

```swift
    func testMoodLookupDeterministicWhenDuplicated() throws {
        let pc = PersistenceController(inMemory: true)
        let ctx = pc.viewContext
        let couple = try CoupleRepository(context: ctx)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        let author = UUID()
        let day = Calendar.current.startOfDay(for: Date())
        let idA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
        let idB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!
        for (uuid, emoji) in [(idB, "😐"), (idA, "😊")] {
            let mood = CDDailyMood(context: ctx)
            mood.id = uuid
            mood.authorPartnerID = author
            mood.day = day
            mood.moodEmoji = emoji
            mood.couple = couple
        }
        try ctx.save()
        let found = DailyMoodRepository(context: ctx)
            .mood(couple: couple, authorID: author, day: day, calendar: .current)
        XCTAssertEqual(found?.id, idA, "重复时必须取 id 字典序最小的一条，两端一致")
    }
```

新建 `Tests/PlanItemIdentityTests.swift`：

```swift
import XCTest
@testable import Anniversary

final class PlanItemIdentityTests: XCTestCase {
    func testPlanItemIdentifiableWitnessIsBusinessUUID() throws {
        let pc = PersistenceController(inMemory: true)
        let item = CDPlanItem(context: pc.viewContext)
        let uuid = UUID()
        item.id = uuid
        func identity<T: Identifiable>(_ value: T) -> T.ID { value.id }
        // 若 Identifiable 见证退化为 ObjectIdentifier，下一行编译失败（类型不符），
        // 即锁定：跨上下文/跨设备的 ForEach 身份 = 业务 UUID，不是类实例地址。
        let resolved: UUID? = identity(item)
        XCTAssertEqual(resolved, uuid)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: `testMoodLookupDeterministicWhenDuplicated` FAIL（set-scan 顺序不定，断言可能间歇过——若本次侥幸通过，把两条插入顺序对调复跑确认不稳定本质）；PlanItem 测试预计直接绿（它是回归锁，不是新行为）。

- [ ] **Step 3: 实现（DailyMoodRepository.mood 替换）**

```swift
    func mood(couple: CDCouple, authorID: UUID?, day: Date, calendar: Calendar) -> CDDailyMood? {
        let normalized = calendar.startOfDay(for: day)
        // CloudKit 禁 unique 约束，双端并发下同 (author, day) 可能短暂重复；
        // 按 id 字典序取首条，保证两端渲染选择一致（后写内容仍以字段级合并策略收敛）。
        // 时区：两位使用者均在东八区，startOfDay 以本机时区归一（spec §9 时间条款）。
        return ((couple.dailyMoods as? Set<CDDailyMood>) ?? [])
            .filter { $0.authorPartnerID == authorID && $0.day == normalized }
            .sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
            .first
    }
```

- [ ] **Step 4: 跑全量测试确认通过**

Run: `./scripts/test.sh`
Expected: `✅ 测试通过`（49 个）。

- [ ] **Step 5: 提交**

```bash
git add Persistence/DailyMoodRepository.swift Tests/DailyMoodRepositoryTests.swift Tests/PlanItemIdentityTests.swift
git commit -m "P2-T5 清账：DailyMood 重复容错确定性选取，PlanItem 身份见证锁定为业务 UUID"
```

---

### Task 6: SharingManager（CKShare 创建/读取/锁定/接受）

**Files:**
- Create: `Persistence/SharingManager.swift`
- Test: `Tests/SharingManagerTests.swift`

**Interfaces:**
- Consumes: `PersistenceController`（container、privateStore、sharedStore，T2）。
- Produces（T7/T8 依赖）:
  - `@MainActor final class SharingManager: ObservableObject`
  - `init(controller: PersistenceController)`
  - `@Published private(set) var share: CKShare?` / `@Published private(set) var lastError: String?`
  - `var participantJoined: Bool` 与 `static func participantJoined(in: CKShare?) -> Bool`
  - `static func configure(_ share: CKShare)`（标题 + publicPermission = .readWrite）
  - `func loadShare(for couple: CDCouple) async`
  - `func ensureShare(for couple: CDCouple) async throws -> CKShare`
  - `func lockInvites() async` （publicPermission → .none，防新人经链接加入）
  - `nonisolated static func accept(_ metadata: CKShare.Metadata)`（T7 的 delegate 调它）

**共享策略（写进注释）：** 链接即可加入（publicPermission .readWrite），链接只经微信私发给她；她加入后设置页出现「锁定邀请」把 publicPermission 关为 .none——门先开、人进来、再锁门。CloudKit 网络行为不可单测，单测只锁纯配置逻辑；端到端由 RELEASE.md 双机清单验收。

- [ ] **Step 1: 写失败测试（新建 Tests/SharingManagerTests.swift）**

```swift
import XCTest
import CloudKit
@testable import Anniversary

final class SharingManagerTests: XCTestCase {
    private func makeShare() -> CKShare {
        CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
    }

    func testConfigureSetsTitleAndOpenPermission() {
        let share = makeShare()
        SharingManager.configure(share)
        XCTAssertEqual(share[CKShare.SystemFieldKey.title] as? String, "我们的纪念空间")
        XCTAssertEqual(share.publicPermission, .readWrite)
    }

    func testParticipantJoinedFalseForNilAndOwnerOnly() {
        XCTAssertFalse(SharingManager.participantJoined(in: nil))
        // 新建 share 只有 owner 一名参与者
        XCTAssertFalse(SharingManager.participantJoined(in: makeShare()))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL——`SharingManager` 不存在。

- [ ] **Step 3: 实现（新建 Persistence/SharingManager.swift）**

```swift
import CloudKit
import CoreData

/// 情侣空间唯一一次配对的全部 CKShare 操作。
/// 策略：链接即可加入（publicPermission .readWrite），链接只经微信私发；
/// 对方加入后由「锁定邀请」把 publicPermission 关为 .none——门先开、人进来、再锁门。
@MainActor
final class SharingManager: ObservableObject {
    static let shareTitle = "我们的纪念空间"

    private let controller: PersistenceController
    @Published private(set) var share: CKShare?
    @Published private(set) var lastError: String?

    init(controller: PersistenceController) {
        self.controller = controller
    }

    var participantJoined: Bool { Self.participantJoined(in: share) }

    /// 除 owner 外存在已接受的参与者
    static func participantJoined(in share: CKShare?) -> Bool {
        guard let share else { return false }
        return share.participants.contains { $0.role != .owner && $0.acceptanceStatus == .accepted }
    }

    static func configure(_ share: CKShare) {
        share[CKShare.SystemFieldKey.title] = Self.shareTitle
        share.publicPermission = .readWrite
    }

    func loadShare(for couple: CDCouple) async {
        do {
            let shares = try controller.container.fetchShares(matching: [couple.objectID])
            share = shares[couple.objectID]
        } catch {
            lastError = "读取配对状态失败"
        }
    }

    /// 已有 share 直接返回；没有则创建（couple 整树迁入共享 zone）、配置并持久化。
    func ensureShare(for couple: CDCouple) async throws -> CKShare {
        if let share { return share }
        if let existing = try controller.container.fetchShares(matching: [couple.objectID])[couple.objectID] {
            share = existing
            return existing
        }
        let (_, newShare, _) = try await controller.container.share([couple], to: nil)
        Self.configure(newShare)
        if let store = controller.privateStore {
            let persisted = try await controller.container.persistUpdatedShare(newShare, in: store)
            share = persisted
            return persisted
        }
        share = newShare
        return newShare
    }

    /// 她加入后关门：新人无法再经链接加入，既有参与者不受影响。
    func lockInvites() async {
        guard let share, let store = controller.privateStore else { return }
        share.publicPermission = .none
        do {
            self.share = try await controller.container.persistUpdatedShare(share, in: store)
        } catch {
            lastError = "锁定失败，请重试"
        }
    }

    /// 受邀方 delegate 入口（T7）。接受后镜像自动把共享 zone 导入共享库，
    /// RootView 的 couple FetchRequest 随之非空，界面自动进入主壳。
    nonisolated static func accept(_ metadata: CKShare.Metadata) {
        let controller = PersistenceController.shared
        guard let sharedStore = controller.sharedStore else { return }
        controller.container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            if let error {
                print("接受邀请失败：\(error)")
            }
        }
    }
}
```

- [ ] **Step 4: 跑全量测试确认通过**

Run: `./scripts/test.sh`
Expected: `✅ 测试通过`（51 个）。

- [ ] **Step 5: 提交**

```bash
git add Persistence/SharingManager.swift Tests/SharingManagerTests.swift
git commit -m "P2-T6 SharingManager：share 创建/读取/锁定与接受入口"
```

---

### Task 7: 接受邀请启动管线 + 引导页第二条路

**Files:**
- Create: `App/AppDelegate.swift`
- Modify: `App/AnniversaryApp.swift`
- Modify: `Features/Onboarding/OnboardingView.swift`

**Interfaces:**
- Consumes: `SharingManager.accept(_:)`（T6）。
- Produces: 点开 CKShare 链接（App 已装）冷/热启动均能接受邀请；引导页有「接受邀请」次按钮 + 等待引导 sheet。**本任务无法单测**（UIKit delegate + CloudKit 网络），验收在 RELEASE.md 双机清单；门禁为构建+既有测试全绿。

**原理（Apple 官方样例路径）：** SwiftUI 生命周期不暴露 CloudKit 分享回调，必须桥 UIKit——`UIApplicationDelegateAdaptor` 挂 AppDelegate，AppDelegate 把 scene 会话指到自定义 SceneDelegate；系统在热启动时回调 `windowScene(_:userDidAcceptCloudKitShareWith:)`，冷启动时把 metadata 放进 `connectionOptions.cloudKitShareMetadata`，两处都要接。

- [ ] **Step 1: 新建 App/AppDelegate.swift**

```swift
import UIKit
import CloudKit

/// SwiftUI 生命周期不暴露 CloudKit 分享接受回调，桥一层 UIKit delegate。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// 热启动：App 在运行/后台时点开邀请链接
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        SharingManager.accept(cloudKitShareMetadata)
    }

    /// 冷启动：点链接把 App 拉起时 metadata 随连接选项进来
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            SharingManager.accept(metadata)
        }
    }
}
```

- [ ] **Step 2: AnniversaryApp 挂 adaptor**

`AnniversaryApp` struct 首行（`private let persistence` 之前）加：

```swift
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
```

- [ ] **Step 3: OnboardingView 加「接受邀请」入口与等待 sheet**

1. `OnboardingView` 加状态：`@State private var showAcceptGuide = false`。
2. 删除底部整行 `Text("P2 阶段这里会出现「接受 TA 的邀请」").dsFootnote()`，原位替换为：

```swift
                Button("接受邀请") { showAcceptGuide = true }
                    .buttonStyle(GhostPillButtonStyle(fullWidth: true))

                Text("TA 已经创建过空间？别再新建，用上面的接受邀请加入。")
                    .dsFootnote()
                    .multilineTextAlignment(.center)
```

3. `ScrollView` 的 `.background(DS.canvas)` 后追加：

```swift
        .sheet(isPresented: $showAcceptGuide) { AcceptInviteGuideSheet() }
```

4. 同文件底部（#Preview 之前）新增：

```swift
/// 接受方指引：接受动作本身由系统链接驱动（SceneDelegate），
/// 本页只负责讲清步骤并陪伴等待；共享数据一到、RootView 自动切主界面。
private struct AcceptInviteGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            let _ = couples.count  // 注册观察：共享空间导入后本 sheet 随 RootView 一起被替换
            Capsule().fill(DS.chipBorder).frame(width: 36, height: 5).padding(.top, 8)
            Text("加入 TA 的空间").dsPageTitle()
            VStack(alignment: .leading, spacing: 10) {
                Text("1. 让 TA 打开 App 设置 → 配对与同步，点「发出邀请」发给你").dsBody()
                Text("2. 在微信里点开那条链接，选择用本 App 打开").dsBody()
                Text("3. 回到这里稍等片刻，空间同步完成会自动进入").dsBody()
            }
            .padding(.horizontal, DS.Spacing.md)
            ProgressView()
            Text("等链接点开后，这里会自动完成").dsFootnote()
            Spacer()
            Button("知道了") { dismiss() }
                .buttonStyle(BluePillButtonStyle(fullWidth: true))
                .padding(.horizontal, DS.Spacing.md)
        }
        .padding(.bottom, DS.Spacing.lg)
        .presentationDetents([.medium])
        .background(DS.canvas)
    }
}
```

（若工程内幽灵药丸按钮样式名不是 `GhostPillButtonStyle`，以 `DesignSystem/DSButtons.swift` 中实际名称为准——先 `grep -n "PillButtonStyle" DesignSystem/DSButtons.swift` 核对，禁止新造样式。）

- [ ] **Step 4: 构建 + 全量测试**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 两个 ✅。

- [ ] **Step 5: 提交**

```bash
git add App/AppDelegate.swift App/AnniversaryApp.swift Features/Onboarding/OnboardingView.swift
git commit -m "P2-T7 接受邀请管线：UIKit delegate 桥接冷热启动，引导页第二条路"
```

---

### Task 8: 设置页「配对与同步」区

**Files:**
- Modify: `Features/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `SharingManager`（T6）、`CoupleRepository.isParticipantDevice(_:)`（T3）、`PersistenceController.cloudContainerID`（T2）。
- Produces: 配对状态可视 + 「生成邀请 / 发出邀请 / 锁定邀请」三态操作 + iCloud 账号状态行。文案按钮均 ≤6 字。

- [ ] **Step 1: SettingsView 加状态与生命周期**

struct 内追加属性：

```swift
    @StateObject private var sharing = SharingManager(controller: .shared)
    @State private var accountAvailable = true
    @State private var creatingShare = false
```

`.onAppear(perform: load)` 之后追加：

```swift
        .task {
            if let couple = couples.first {
                await sharing.loadShare(for: couple)
            }
            let status = try? await CKContainer(identifier: PersistenceController.cloudContainerID).accountStatus()
            accountAvailable = status == .available
        }
```

文件顶部 `import SwiftUI` 下加 `import CloudKit`。

- [ ] **Step 2: 插入配对与同步区**

在「显示」section 之后、footnote 之前插入：

```swift
                Text("配对与同步").dsSectionTitle()
                GroupedSection {
                    GroupedRow(title: "配对状态", value: pairingStatusText,
                               valueColor: pairingStatusDone ? DS.dsGreen : DS.inkMuted)
                    if let couple = couples.first,
                       !CoupleRepository(context: context).isParticipantDevice(couple) {
                        if let url = sharing.share?.url {
                            ShareLink(item: url) {
                                GroupedRow(title: "邀请链接", value: "发出邀请 ›", valueColor: DS.actionBlue)
                            }
                            .buttonStyle(.plain)
                            if sharing.participantJoined, sharing.share?.publicPermission != .none {
                                Button {
                                    Task { await sharing.lockInvites() }
                                } label: {
                                    GroupedRow(title: "对方已加入", value: "锁定邀请 ›", valueColor: DS.actionBlue)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
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
                        }
                    }
                    GroupedRow(title: "iCloud 账号", value: accountAvailable ? "正常" : "未登录",
                               valueColor: accountAvailable ? DS.dsGreen : DS.dsRed, showsDivider: false)
                    if let error = sharing.lastError {
                        Text(error).font(.system(size: 12)).foregroundStyle(DS.dsRed)
                            .padding(.horizontal, 14).padding(.bottom, 8)
                    }
                }
```

同文件底部加计算属性：

```swift
    private var pairingStatusText: String {
        guard let couple = couples.first else { return "未配对" }
        if CoupleRepository(context: context).isParticipantDevice(couple) { return "已连接" }
        if sharing.participantJoined { return "已连接" }
        if sharing.share != nil { return "邀请已发出" }
        return "未配对"
    }

    private var pairingStatusDone: Bool { pairingStatusText == "已连接" }
```

footnote 行 `Text("配对与同步在 P2 阶段开启 · 版本 …")` 改为 `Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")`。

（`GroupedRow` 的参数签名以 `DesignSystem/DSCards.swift` 实际定义为准，先 grep 核对 `showsDivider`/`valueColor` 默认值；`DS.dsGreen`/`DS.dsRed` 若命名不同以 `DS.swift` 为准，禁止新加色令牌。）

- [ ] **Step 3: 构建 + 全量测试**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 两个 ✅。模拟器未登录 iCloud 时该区显示「未登录」属正确行为。

- [ ] **Step 4: 提交**

```bash
git add Features/Settings/SettingsView.swift
git commit -m "P2-T8 设置页配对与同步区：三态邀请操作与账号状态"
```

---

### Task 9: 对方补评（写入路径）

**Files:**
- Modify: `Persistence/MomentRepository.swift`（追加 upsertEvaluation）
- Create: `Features/Moments/EvaluationFormSheet.swift`
- Modify: `Features/Moments/MomentDetailView.swift`（「补上评价」按钮）
- Test: `Tests/MomentRepositoryTests.swift`（追加）

**Interfaces:**
- Consumes: `NewEvaluation`（P1 既有 struct：stars/moodEmoji/comment）、`currentPartnerID(of:)`（T3）、`StarInputView`/`EmojiPickerRow`（DesignSystem 既有）。
- Produces: `MomentRepository.upsertEvaluation(on moment: CDMoment, by authorID: UUID?, _ new: NewEvaluation) throws -> CDEvaluation`（@discardableResult）；详情页在“我还没写”时出现补评入口（她的设备补她那半、你的设备补你那半，同一套代码）。

- [ ] **Step 1: 写失败测试（追加到 Tests/MomentRepositoryTests.swift）**

```swift
    func testUpsertEvaluationCreatesThenUpdates() throws {
        let pc = PersistenceController(inMemory: true)
        let ctx = pc.viewContext
        let couple = try CoupleRepository(context: ctx)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        let meetings = MeetingRepository(context: ctx)
        let meeting = try meetings.createPlanned(couple: couple, title: nil, city: nil, plannedStart: nil)
        try meetings.start(meeting, at: Date())
        let repo = MomentRepository(context: ctx)
        let moment = try repo.create(in: meeting, type: .restaurant, title: "小馆子", body: nil,
                                     happenedAt: Date(), photoDatas: [], myEvaluation: nil,
                                     authorID: nil, place: nil)
        let her = UUID()

        let created = try repo.upsertEvaluation(on: moment, by: her,
                                                NewEvaluation(stars: 4, moodEmoji: "😊", comment: "好吃"))
        XCTAssertEqual(repo.evaluation(of: moment, by: her)?.objectID, created.objectID)
        XCTAssertEqual(created.stars, 4)

        let updated = try repo.upsertEvaluation(on: moment, by: her,
                                                NewEvaluation(stars: 5, moodEmoji: "🥰", comment: "改口，超好吃"))
        XCTAssertEqual(updated.objectID, created.objectID, "同作者第二次写入必须是更新不是新建")
        XCTAssertEqual(((moment.evaluations as? Set<CDEvaluation>) ?? []).count, 1)
        XCTAssertEqual(repo.evaluation(of: moment, by: her)?.stars, 5)
        XCTAssertEqual(repo.evaluation(of: moment, by: her)?.comment, "改口，超好吃")
    }
```

（`createPlanned`/`start` 的确切参数以 `Persistence/MeetingRepository.swift` 现有签名为准，先 grep 核对再写测试；若 `createPlanned` 需要更多参数，按最小必填补齐。）

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL——`upsertEvaluation` 不存在。

- [ ] **Step 3: 实现 upsertEvaluation（MomentRepository.swift，追加在 evaluation(of:by:) 之后）**

```swift
    /// 补评/改评的唯一写入口：同 (moment, author) 存在则更新，否则创建。
    @discardableResult
    func upsertEvaluation(on moment: CDMoment, by authorID: UUID?, _ new: NewEvaluation) throws -> CDEvaluation {
        let evaluation: CDEvaluation
        if let existing = self.evaluation(of: moment, by: authorID) {
            evaluation = existing
        } else {
            evaluation = CDEvaluation(context: context)
            evaluation.id = UUID()
            evaluation.authorPartnerID = authorID
            evaluation.moment = moment
        }
        evaluation.stars = new.stars
        evaluation.moodEmoji = new.moodEmoji
        evaluation.comment = new.comment
        try context.save()
        return evaluation
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `./scripts/test.sh`
Expected: `✅ 测试通过`（52 个）。

- [ ] **Step 5: 新建 Features/Moments/EvaluationFormSheet.swift**

```swift
import SwiftUI

/// 给一条记忆补/改“我这一半”的评价。两台设备同一套代码：
/// authorID 由 currentPartnerID 解析，她的设备写她那半。
struct EvaluationFormSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let moment: CDMoment
    @State private var stars = 5
    @State private var moodEmoji: String?
    @State private var comment = ""
    @State private var saveFailed = false

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Capsule().fill(DS.chipBorder).frame(width: 36, height: 5).padding(.top, 8)
            Text("补上我的评价").dsPageTitle()
            ParchmentCard {
                VStack(alignment: .leading, spacing: 12) {
                    StarInputView(stars: $stars)
                    EmojiPickerRow(selection: $moodEmoji)
                    TextField("一句话短评（可选）", text: $comment)
                        .textFieldStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            Button("保存") {
                let couples = CoupleRepository(context: context)
                guard let couple = try? couples.fetchCouple() else { return }
                do {
                    try MomentRepository(context: context).upsertEvaluation(
                        on: moment,
                        by: couples.currentPartnerID(of: couple),
                        NewEvaluation(stars: Int16(stars), moodEmoji: moodEmoji,
                                      comment: comment.isEmpty ? nil : comment))
                    dismiss()
                } catch {
                    saveFailed = true
                }
            }
            .buttonStyle(BluePillButtonStyle(fullWidth: true))
            .padding(.horizontal, DS.Spacing.md)
            if saveFailed {
                Text("保存失败，请重试").font(.system(size: 13)).foregroundStyle(DS.dsRed)
            }
            Spacer()
        }
        .presentationDetents([.medium])
        .background(DS.canvas)
    }
}
```

（已核对：`StarInputView(stars: Binding<Int>)`、`EmojiPickerRow(selection: Binding<String?>)`，与上面代码一致。）

- [ ] **Step 6: MomentDetailView 挂补评入口**

1. 加状态：`@State private var showEvalForm = false`。
2. T4 改过的评价卡里，我方 else 分支 `Text("你还没写评价").dsCaption()` 替换为：

```swift
                            Button("补上评价") { showEvalForm = true }
                                .buttonStyle(GhostPillButtonStyle(fullWidth: false))
```

3. `.sheet(isPresented: $showEdit) …` 之后追加：

```swift
        .sheet(isPresented: $showEvalForm) { EvaluationFormSheet(moment: moment) }
```

- [ ] **Step 7: 构建 + 全量测试**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 两个 ✅。

- [ ] **Step 8: 提交**

```bash
git add Persistence/MomentRepository.swift Features/Moments Tests/MomentRepositoryTests.swift
git commit -m "P2-T9 对方补评：upsertEvaluation 与补评表单"
```

---

### Task 10: 远程导入监听 → 「TA 记了新回忆」通知

**Files:**
- Create: `Persistence/HistoryMonitor.swift`
- Create: `Support/LocalNotifier.swift`
- Modify: `App/AnniversaryApp.swift`（AppServices 启动）
- Test: `Tests/HistoryMonitorTests.swift`

**Interfaces:**
- Consumes: `PersistenceController.localTransactionAuthor`（T2）、`CoupleRepository.currentPartnerID`（T3）。
- Produces:
  - `protocol MomentNotifying { func notifyNewMoments(titles: [String]) }`
  - `final class HistoryMonitor` 带 `init(container: NSPersistentContainer, localAuthor: String, notifier: MomentNotifying, defaults: UserDefaults, isEnabled: @escaping () -> Bool, myPartnerID: @escaping (NSManagedObjectContext) -> UUID?)`、`func start()`、`func processChanges()`（**myPartnerID 接收 monitor 的后台 context**——闭包在后台队列执行，绝不能碰 viewContext）
  - `struct LocalNotifier: MomentNotifying`
  - `enum AppServices { static let historyMonitor: HistoryMonitor }`
  - UserDefaults 开关键：`"newMomentAlertOn"`（缺省 true，T11 的设置页开关共用）

**机制（写进注释）：** CloudKit 静默推送唤起镜像导入 → store 发 `NSPersistentStoreRemoteChange` → 查 persistent history 中**事务作者 ≠ 本机作者**的新增 CDMoment（再滤掉 author 是自己的，防自己另一台设备）→ 发本地通知；token 存 UserDefaults 防重复。App 没被唤醒时通知会迟到，首页提醒区（T12 数据驱动）兜底——诚实的尽力而为。

- [ ] **Step 1: 写失败测试（新建 Tests/HistoryMonitorTests.swift）**

```swift
import XCTest
import CoreData
@testable import Anniversary

private final class SpyNotifier: MomentNotifying {
    var calls: [[String]] = []
    func notifyNewMoments(titles: [String]) { calls.append(titles) }
}

final class HistoryMonitorTests: XCTestCase {
    private var tmpDir: URL!
    private var container: NSPersistentContainer!
    private var defaults: UserDefaults!
    private let suite = "HistoryMonitorTests"

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        container = NSPersistentContainer(name: "T", managedObjectModel: ModelSchema.model)
        let desc = NSPersistentStoreDescription(url: tmpDir.appendingPathComponent("t.sqlite"))
        desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, e in if let e { loadError = e } }
        XCTAssertNil(loadError)
        container.viewContext.transactionAuthor = "AnniversaryApp"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        container = nil
        try? FileManager.default.removeItem(at: tmpDir)
    }

    /// 造一条“像镜像导入”的事务：后台 context、作者不是本机
    private func importPartnerMoment(title: String, author authorID: UUID) throws {
        let bg = container.newBackgroundContext()
        bg.transactionAuthor = "NSCloudKitMirroringDelegate.import"
        var thrown: Error?
        bg.performAndWait {
            let moment = CDMoment(context: bg)
            moment.id = UUID()
            moment.title = title
            moment.typeRaw = 0
            moment.createdAt = Date()
            moment.authorPartnerID = authorID
            do { try bg.save() } catch { thrown = error }
        }
        if let thrown { throw thrown }
    }

    private func makeMonitor(notifier: SpyNotifier, enabled: Bool = true, me: UUID) -> HistoryMonitor {
        HistoryMonitor(container: container, localAuthor: "AnniversaryApp",
                       notifier: notifier, defaults: defaults,
                       isEnabled: { enabled }, myPartnerID: { _ in me })
    }

    func testPartnerImportTriggersNotificationOnce() throws {
        let me = UUID(), her = UUID()
        let spy = SpyNotifier()
        let monitor = makeMonitor(notifier: spy, me: me)
        try importPartnerMoment(title: "外滩夜景", author: her)
        monitor.processChanges()
        XCTAssertEqual(spy.calls, [["外滩夜景"]])
        monitor.processChanges()
        XCTAssertEqual(spy.calls.count, 1, "token 前进后不得重复通知")
    }

    func testOwnLocalWritesDoNotNotify() throws {
        let me = UUID()
        let spy = SpyNotifier()
        let monitor = makeMonitor(notifier: spy, me: me)
        let moment = CDMoment(context: container.viewContext)
        moment.id = UUID(); moment.title = "我自己记的"; moment.typeRaw = 0
        moment.createdAt = Date(); moment.authorPartnerID = me
        try container.viewContext.save()
        monitor.processChanges()
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testDisabledStillAdvancesTokenSilently() throws {
        let me = UUID(), her = UUID()
        let spy = SpyNotifier()
        let muted = makeMonitor(notifier: spy, enabled: false, me: me)
        try importPartnerMoment(title: "静音期记录", author: her)
        muted.processChanges()
        XCTAssertTrue(spy.calls.isEmpty)
        let loud = makeMonitor(notifier: spy, enabled: true, me: me)
        try importPartnerMoment(title: "开启后记录", author: her)
        loud.processChanges()
        XCTAssertEqual(spy.calls, [["开启后记录"]], "静音期条目不补发，token 已消化")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL——`HistoryMonitor`/`MomentNotifying` 不存在。

- [ ] **Step 3: 实现（新建 Persistence/HistoryMonitor.swift）**

```swift
import CoreData

protocol MomentNotifying {
    func notifyNewMoments(titles: [String])
}

/// 远程导入监听：镜像把对方的写入合进本地库时（NSPersistentStoreRemoteChange），
/// 从 persistent history 里挑出「事务作者 ≠ 本机」的新增 CDMoment 发本地通知。
/// App 未被唤醒时通知会迟到，首页提醒区（数据驱动）兜底——尽力而为，不做保证。
final class HistoryMonitor {
    static let tokenKey = "historyMonitor.token.v1"

    private let container: NSPersistentContainer
    private let localAuthor: String
    private let notifier: MomentNotifying
    private let defaults: UserDefaults
    private let isEnabled: () -> Bool
    /// 在 monitor 的后台 context 队列内被调用，实现只能用传入的 context 取数
    private let myPartnerID: (NSManagedObjectContext) -> UUID?
    private var observer: NSObjectProtocol?

    init(container: NSPersistentContainer, localAuthor: String, notifier: MomentNotifying,
         defaults: UserDefaults = .standard,
         isEnabled: @escaping () -> Bool, myPartnerID: @escaping (NSManagedObjectContext) -> UUID?) {
        self.container = container
        self.localAuthor = localAuthor
        self.notifier = notifier
        self.defaults = defaults
        self.isEnabled = isEnabled
        self.myPartnerID = myPartnerID
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator, queue: nil) { [weak self] _ in
            self?.processChanges()
        }
    }

    func processChanges() {
        let context = container.newBackgroundContext()
        context.performAndWait {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: loadToken())
            request.resultType = .transactionsAndChanges
            guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction],
                  !transactions.isEmpty else { return }

            var insertedMomentIDs: [NSManagedObjectID] = []
            for transaction in transactions where transaction.author != localAuthor {
                for change in transaction.changes ?? []
                where change.changeType == .insert && change.changedObjectID.entity.name == "CDMoment" {
                    insertedMomentIDs.append(change.changedObjectID)
                }
            }
            if let last = transactions.last { saveToken(last.token) }

            guard isEnabled(), !insertedMomentIDs.isEmpty else { return }
            let me = myPartnerID(context)
            let titles: [String] = insertedMomentIDs.compactMap { id in
                guard let moment = try? context.existingObject(with: id) as? CDMoment else { return nil }
                if let me, moment.authorPartnerID == me { return nil }  // 自己另一台设备写的不提醒
                return moment.title ?? "新回忆"
            }
            if !titles.isEmpty {
                notifier.notifyNewMoments(titles: titles)
            }
        }
    }

    private func loadToken() -> NSPersistentHistoryToken? {
        guard let data = defaults.data(forKey: Self.tokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
    }

    private func saveToken(_ token: NSPersistentHistoryToken) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        defaults.set(data, forKey: Self.tokenKey)
    }
}
```

- [ ] **Step 4: 实现通知器（新建 Support/LocalNotifier.swift）**

```swift
import UserNotifications

struct LocalNotifier: MomentNotifying {
    func notifyNewMoments(titles: [String]) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "TA 记了新回忆"
            content.body = titles.count == 1
                ? "「\(titles[0])」 · 补上你那一半评价"
                : "\(titles.count) 条新回忆 · 补上你那一半评价"
            content.sound = .default
            let request = UNNotificationRequest(identifier: "new-moment-\(UUID().uuidString)",
                                                content: content, trigger: nil)
            center.add(request)
        }
    }
}
```

- [ ] **Step 5: App 启动接线（App/AnniversaryApp.swift）**

文件顶部 struct 外新增：

```swift
/// 进程级服务：只初始化一次（static let 天然防重）。
enum AppServices {
    static let historyMonitor: HistoryMonitor = {
        let controller = PersistenceController.shared
        let monitor = HistoryMonitor(
            container: controller.container,
            localAuthor: PersistenceController.localTransactionAuthor,
            notifier: LocalNotifier(),
            isEnabled: { (UserDefaults.standard.object(forKey: "newMomentAlertOn") as? Bool) ?? true },
            myPartnerID: { backgroundContext in
                // 闭包在 monitor 的后台队列执行，只能用传入的 context——严禁碰 viewContext
                let repo = CoupleRepository(context: backgroundContext)
                guard let couple = try? repo.fetchCouple() else { return nil }
                return repo.currentPartnerID(of: couple)
            })
        monitor.start()
        return monitor
    }()
}
```

`AnniversaryApp` 加初始化器：

```swift
    init() {
        _ = AppServices.historyMonitor
    }
```

- [ ] **Step 6: 跑全量测试确认通过**

Run: `./scripts/test.sh`
Expected: `✅ 测试通过`（55 个）。

- [ ] **Step 7: 提交**

```bash
git add Persistence/HistoryMonitor.swift Support/LocalNotifier.swift App/AnniversaryApp.swift Tests/HistoryMonitorTests.swift
git commit -m "P2-T10 远程导入监听：对方新记忆触发本地通知，token 防重"
```

---

### Task 11: 23:30 封盘提醒 + 设置页通知开关

**Files:**
- Create: `Support/SealReminder.swift`
- Modify: `Features/Moments/MomentFormView.swift`、`Features/Meetings/SealSheet.swift`、`Features/Moments/StaleSealSheet.swift`、`Features/Meetings/MeetingDetailView.swift`、`App/MainShell.swift`（保存/封盘/结束/进前台后各对账一次）
- Modify: `Features/Settings/SettingsView.swift`（通知开关区）
- Test: `Tests/SealReminderTests.swift`

**Interfaces:**
- Consumes: `MeetingRepository`（`ongoingMeeting`/`openDay` —— 确切签名先 `grep -n "func ongoingMeeting\|func openDay" Persistence/MeetingRepository.swift` 核对）、`CoupleRepository.fetchCouple()`。
- Produces:
  - `enum SealReminderDecision: Equatable { case schedule(Date); case cancel }`
  - `enum SealReminderPlanner { static func decision(hasOpenDay: Bool, enabled: Bool, now: Date, calendar: Calendar) -> SealReminderDecision }`（纯函数）
  - `enum SealReminder { static let identifier = "seal-reminder-2330"; static func refresh(context: NSManagedObjectContext, now: Date = Date()) }`（幂等对账：算出该有的状态后覆盖式重排/取消）
  - UserDefaults 键：`"sealReminderOn"`（缺省 true）；设置页两枚开关（封盘提醒 / 新记忆提醒，后者共用 T10 的 `"newMomentAlertOn"`）

**规则（spec §8-4）：** 见面进行中存在未封盘约会日 → 在下一个 23:30 弹本地提醒（现在已过 23:30 则次日 23:30）；没有开着的约会日或开关关闭 → 取消待发提醒。

- [ ] **Step 1: 写失败测试（新建 Tests/SealReminderTests.swift）**

```swift
import XCTest
@testable import Anniversary

final class SealReminderTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ h: Int, _ m: Int) -> Date {
        calendar.date(bySettingHour: h, minute: m, second: 0, of: Date())!
    }

    func testOpenDayBeforeHalfPastElevenSchedulesToday() {
        let now = date(21, 0)
        let decision = SealReminderPlanner.decision(hasOpenDay: true, enabled: true, now: now, calendar: calendar)
        XCTAssertEqual(decision, .schedule(date(23, 30)))
    }

    func testOpenDayAfterHalfPastElevenSchedulesTomorrow() {
        let now = date(23, 45)
        let expected = calendar.date(byAdding: .day, value: 1, to: date(23, 30))!
        XCTAssertEqual(SealReminderPlanner.decision(hasOpenDay: true, enabled: true, now: now, calendar: calendar),
                       .schedule(expected))
    }

    func testExactlyHalfPastElevenSchedulesTomorrow() {
        let now = date(23, 30)
        let expected = calendar.date(byAdding: .day, value: 1, to: date(23, 30))!
        XCTAssertEqual(SealReminderPlanner.decision(hasOpenDay: true, enabled: true, now: now, calendar: calendar),
                       .schedule(expected))
    }

    func testNoOpenDayCancels() {
        XCTAssertEqual(SealReminderPlanner.decision(hasOpenDay: false, enabled: true, now: date(21, 0), calendar: calendar),
                       .cancel)
    }

    func testDisabledCancelsEvenWithOpenDay() {
        XCTAssertEqual(SealReminderPlanner.decision(hasOpenDay: true, enabled: false, now: date(21, 0), calendar: calendar),
                       .cancel)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./scripts/test.sh`
Expected: FAIL——`SealReminderPlanner` 不存在。

- [ ] **Step 3: 实现（新建 Support/SealReminder.swift）**

```swift
import CoreData
import UserNotifications

enum SealReminderDecision: Equatable {
    case schedule(Date)
    case cancel
}

enum SealReminderPlanner {
    /// spec §8-4：开着的约会日存在且开关开 → 下一个 23:30 提醒；否则取消。
    /// 恰在 23:30 触发时视为已过（> 而非 >=），排到次日。
    static func decision(hasOpenDay: Bool, enabled: Bool, now: Date, calendar: Calendar) -> SealReminderDecision {
        guard hasOpenDay, enabled else { return .cancel }
        var target = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: now)!
        if target <= now {
            target = calendar.date(byAdding: .day, value: 1, to: target)!
        }
        return .schedule(target)
    }
}

enum SealReminder {
    static let identifier = "seal-reminder-2330"

    /// 幂等对账：任何可能改变“开着的约会日”状态的动作之后调用一次，
    /// 按当前真实状态覆盖式重排或取消，不累积、不重复。
    static func refresh(context: NSManagedObjectContext, now: Date = Date()) {
        let enabled = (UserDefaults.standard.object(forKey: "sealReminderOn") as? Bool) ?? true
        let hasOpenDay: Bool = {
            guard let couple = try? CoupleRepository(context: context).fetchCouple() else { return false }
            let repo = MeetingRepository(context: context)
            guard let ongoing = try? repo.ongoingMeeting(couple: couple), let ongoing else { return false }
            return ((try? repo.openDay(in: ongoing)) ?? nil) != nil
        }()

        let center = UNUserNotificationCenter.current()
        switch SealReminderPlanner.decision(hasOpenDay: hasOpenDay, enabled: enabled, now: now, calendar: .current) {
        case .cancel:
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
        case .schedule(let date):
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                let content = UNMutableNotificationContent()
                content.title = "今天到此为止？"
                content.body = "还开着约会日 · 睡前记得封盘"
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            }
        }
    }
}
```

（`ongoingMeeting` 若实际签名无 `couple:` 参数或返回非可选，按真实签名适配 `hasOpenDay` 闭包内三行，其余不动。）

- [ ] **Step 4: 跑测试确认通过**

Run: `./scripts/test.sh`
Expected: `✅ 测试通过`（60 个）。

- [ ] **Step 5: 接线四个动作点 + 进前台对账**

各文件在**动作成功之后**（save 成功、dismiss 之前）追加一行 `SealReminder.refresh(context: context)`：
1. `Features/Moments/MomentFormView.swift`：保存记忆成功处（新记录可能开新约会日）。
2. `Features/Meetings/SealSheet.swift`：封盘成功处。
3. `Features/Moments/StaleSealSheet.swift`：补封成功处。
4. `Features/Meetings/MeetingDetailView.swift`：「结束见面」确认成功处（结束会连带封盘）。
5. `App/MainShell.swift`：最外层视图加 `.onAppear { SealReminder.refresh(context: context) }`（冷启动/隔天打开时对账；MainShell 若无 `@Environment(\.managedObjectContext)` 则补上）。

先 `grep -n "try\? .*seal\|try .*seal\|save()" <文件>` 找准每处成功分支，放在 `dismiss()` 之前。

- [ ] **Step 6: 设置页通知开关**

`SettingsView` 属性区追加：

```swift
    @AppStorage("sealReminderOn") private var sealReminderOn = true
    @AppStorage("newMomentAlertOn") private var newMomentAlertOn = true
```

「显示」section 之后（配对区之前）插入：

```swift
                Text("通知").dsSectionTitle()
                GroupedSection {
                    Toggle("封盘提醒", isOn: $sealReminderOn)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .onChange(of: sealReminderOn) { _, _ in
                            SealReminder.refresh(context: context)
                        }
                    DS.hairline.frame(height: 1).padding(.leading, 14)
                    Toggle("新记忆提醒", isOn: $newMomentAlertOn)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                }
```

- [ ] **Step 7: 构建 + 全量测试**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 两个 ✅。

- [ ] **Step 8: 提交**

```bash
git add Support/SealReminder.swift Features App/MainShell.swift Tests/SealReminderTests.swift
git commit -m "P2-T11 封盘提醒：23:30 计划器纯函数、四动作点对账与通知开关"
```

---

### Task 12: 首页提醒区待补评行 + 同步暂停横幅

**Files:**
- Modify: `Features/Home/HomeView.swift`

**Interfaces:**
- Consumes: `MomentRepository.evaluation(of:by:)`、`CoupleRepository.currentPartner(of:)`（T3）。
- Produces: 提醒区聚合「忘封盘 + 待补评」；iCloud 未登录时页顶横幅「同步已暂停」。spec §6-① 提醒区、§9 同步条款落地。

- [ ] **Step 1: 加数据源与账号状态**

`HomeView` 属性区追加（`planItems` fetch 之后）：

```swift
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDMoment.happenedAt, order: .reverse)])
    private var momentsAll: FetchedResults<CDMoment>
    @State private var accountAvailable = true
```

文件顶部补 `import CloudKit`。body 里的观察行改为：

```swift
            let _ = (moods.count, dateDays.count, planItems.count, momentsAll.count)  // 注册观察：心情/约会日/计划项/记忆（含对方同步进来的）变更均刷新首页
```

`ScrollView` 修饰链（`.sheet` 之前）追加：

```swift
        .task { await refreshAccountStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            Task { await refreshAccountStatus() }
        }
```

文件底部加：

```swift
    @MainActor
    private func refreshAccountStatus() async {
        let status = try? await CKContainer(identifier: PersistenceController.cloudContainerID).accountStatus()
        accountAvailable = status == .available
    }
```

- [ ] **Step 2: 页顶横幅**

`VStack` 内 `header(couple)` 之前插入：

```swift
                    if !accountAvailable {
                        ParchmentCard {
                            HStack(spacing: 8) {
                                Circle().fill(DS.dsRed).frame(width: 6, height: 6)
                                Text("同步已暂停 · 登录 iCloud 后自动恢复").dsCaption()
                            }
                        }
                    }
```

- [ ] **Step 3: 提醒区聚合待补评**

`reminders(_:)` 函数整体替换为：

```swift
    @ViewBuilder
    private func reminders(_ couple: CDCouple) -> some View {
        let meetingRepo = MeetingRepository(context: context)
        let momentRepo = MomentRepository(context: context)
        let ongoing = meetings.first { $0.statusRaw == MeetingStatus.ongoing.rawValue }
        let stale = ongoing.flatMap { try? meetingRepo.staleOpenDay(in: $0, now: Date()) } ?? nil
        let myID = CoupleRepository(context: context).currentPartnerID(of: couple)
        let pendingEvals = Array(momentsAll.filter { momentRepo.evaluation(of: $0, by: myID) == nil }.prefix(3))

        Text("提醒").dsSectionTitle()
        GroupedSection {
            if stale == nil && pendingEvals.isEmpty {
                GroupedRow(title: "一切都好", value: "去足迹翻翻回忆 ›", showsDivider: false)
            } else {
                if let ongoing, stale != nil {
                    NavigationLink {
                        MeetingDetailView(meeting: ongoing)
                    } label: {
                        GroupedRow(title: "昨天忘了封盘？", value: "去封盘 ›",
                                   valueColor: DS.actionBlue, showsDivider: !pendingEvals.isEmpty)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(Array(pendingEvals.enumerated()), id: \.element.objectID) { i, moment in
                    NavigationLink {
                        MomentDetailView(moment: moment)
                    } label: {
                        GroupedRow(title: "「\(moment.title ?? "新回忆")」还没写你的评价",
                                   value: "去补评 ›", valueColor: DS.actionBlue,
                                   showsDivider: i < pendingEvals.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
```

- [ ] **Step 4: 构建 + 全量测试**

Run: `./scripts/build.sh && ./scripts/test.sh`
Expected: 两个 ✅。既有首页空态（无提醒时「一切都好」）不回归；有未评价记忆时 P1 的本机数据也会出现补评行——语义正确（“你那一半”从来含本机）。

- [ ] **Step 5: 提交**

```bash
git add Features/Home/HomeView.swift
git commit -m "P2-T12 首页：待补评提醒行与 iCloud 同步暂停横幅"
```

---

### Task 13: 发布手册 RELEASE.md + 版本号 0.2.0 + 收尾

**Files:**
- Create: `docs/RELEASE.md`
- Modify: `project.yml`（MARKETING_VERSION → 0.2.0）

**Interfaces:** 无代码接口；产出运营手册与最终门禁。

- [ ] **Step 1: 写 docs/RELEASE.md（完整内容如下，原样落盘）**

````markdown
# 发布与双机部署手册（P2 · TestFlight + CloudKit 生产）

固定事实：Team ID `N4YSFLZ44L`（个人账号，Kecheng Feng）· Bundle ID `com.fkc.anniversary` · 云容器 `iCloud.com.fkc.anniversary` · 版本 0.2.0。
个人开发者账号**没有多人内部团队**：你自己 = 内部测试员（免审、秒到），她 = **外部测试员**（首个构建需 Beta App Review，约 1–2 天）。

## 关键认知：环境是两个平行世界

- 从 Xcode 直接 ⌘R 装的开发构建 → CloudKit **Development** 环境。
- TestFlight / App Store 构建 → CloudKit **Production** 环境。
- **两个环境的数据互不相通。** 所以最终两人都用 TestFlight 构建（你走内部、她走外部），日常不要再用 ⌘R 版本记录数据。

## 一、CloudKit schema：初始化（Development）→ 部署（Production）

1. Xcode 打开工程 → 顶部 scheme「Anniversary」→ Edit Scheme… → Run → Arguments，勾选已预置的 `-InitCloudKitSchema`。
2. 用**你的 iPhone**（已登录你的 iCloud）⌘R 跑一次，控制台见 `✅ CloudKit schema 初始化完成（Development 环境）`。它会把 15 个实体的记录类型一次性建全（含 P4/P5 还没数据的实体——一次部署，后面阶段不用再来）。
3. 取消勾选该参数。
4. 浏览器打开 https://icloud.developer.apple.com → 容器 `iCloud.com.fkc.anniversary` → 左下 **Deploy Schema Changes…** → 从 Development 部署到 **Production**。看到 CD 开头的 15 个记录类型全被带上即确认。

## 二、App Store Connect 建 App

1. https://appstoreconnect.apple.com → 我的 App → ＋ → 新建 App。
2. 平台 iOS；名称先用 `Anniversary`（正式名想好后可改）；主要语言 简体中文；Bundle ID 选 `com.fkc.anniversary`；SKU 填 `anniversary-yu`。
3. TestFlight 外部测试要求填「Beta 版 App 信息」：反馈邮箱填你的邮箱；隐私政策 URL 必填——可让 Claude 生成一页静态说明（“数据仅存于两台设备与你们的 iCloud 私有库，无第三方服务器”）挂在 GitHub Pages。

## 三、归档上传

1. Xcode 设备选择器选 **Any iOS Device (arm64)**。
2. 菜单 Product → **Archive**。
3. 弹出 Organizer → Distribute App → **TestFlight & App Store** → Upload，一路默认（自动签名会把 aps-environment 切成 production）。
4. App Store Connect → TestFlight 标签页，等构建处理完（10–30 分钟，会邮件通知）。出现「出口合规」问题时因 Info.plist 已带 `ITSAppUsesNonExemptEncryption=false` 通常自动通过。

## 四、你自己先装（内部测试，免审）

1. TestFlight 页 → 内部测试 → ＋ 新建群组「我们」→ 添加测试员：选你自己的账号。
2. iPhone 装 **TestFlight** App（App Store 免费）→ 邮件邀请里点 View in TestFlight → 安装。
3. **数据无缝衔接**：TestFlight 构建按同 Bundle ID 原地覆盖 ⌘R 构建，本地 P1 数据全保留；首启后镜像把存量数据全量导出到 Production。
4. **验证导出**（必做）：CloudKit Console → Production → Data → 查询 `CD_CDMeeting` 记录，条数 ≥ 你的见面数。10 分钟还不见数据 → 停下，回来找 Claude（回退方案：暂时继续用 ⌘R 构建，等补导出工具，勿再让她装）。

## 五、她装（外部测试，需 Beta 审核）

1. TestFlight 页 → 外部测试 → ＋ 群组「小于」→ 启用**公开链接**。
2. 把构建加入该群组 → 填测试信息 → **提交 Beta App Review**（1–2 天，个人纪念 App 一般秒过）。
3. 审核过后把公开链接微信发她：她 iPhone 装 TestFlight App → 点链接 → 安装 Anniversary。

## 六、配对（一次性仪式）

1. **你**：App 设置 → 配对与同步 → 「生成邀请」→ 「发出邀请」→ 微信发她。
2. **她**：先装好 App（第五步）→ 微信点开链接 → 选「用 Anniversary 打开」→ App 引导页停几秒，空间同步完成自动进入主界面（数据多时首次同步几分钟）。
3. **你**：回设置页看到「已连接」→ 点「**锁定邀请**」（关门：此后链接失效，旁人无法加入）。
4. 她设置页此后显示「已连接」；她改自己昵称，你那边几秒后可见。

## 七、双机验收清单（配对完成后逐条打勾）

1. 你新建记忆（带照片）→ 她 30 秒内可见，照片清晰。
2. 她对同条记忆「补上评价」→ 你端时间线两行评价齐了。
3. 你收到通知「TA 记了新回忆」？（她记一条新的试）App 在后台时可能迟到，打开 App 首页提醒区必有「去补评」行。
4. 心情：两人各自打卡 → 双方首页心情卡两个 emoji。
5. 行前计划：她添加一条日程、你勾选完成 → 双向同步。
6. 离线：她开飞行模式记一条 → 恢复网络后自动到你端。
7. 并发：两人同时改同一条记忆标题 → 数秒后两端一致（后写胜，不崩溃）。
8. 封盘状态机：你端封盘 → 她端时间线出现晚安卡。
9. 23:30 封盘提醒：见面进行中不封盘，等到 23:30（或把手机时间拨到 23:29 等一分钟）→ 本地通知到达。
10. 设置改名：你改她昵称 → 她端更新（反向亦然）。
11. **补封拦截手测（P1 挂账①）**：真机设置 → 通用 → 日期与时间 → 关自动、把时间拨快 19 小时 → 回 App 记一条新记忆 → 必弹「昨天是不是忘了封盘？」补封 sheet；测完把时间改回自动。
12. 锁定邀请后：把旧链接再点一次 → 提示无法加入（预期失败）。

## 八、故障速查

- 「同步已暂停」横幅：设备没登录 iCloud 或 iCloud Drive 关闭 → 设置里登录/打开后自动恢复。
- 她点链接没反应：确认她已先装 App（链接要由 App 接）；App 已装仍不行 → 卸载重装后再点链接。
- 两端数据长时间不一致：双方都打开 App 放前台一分钟（静默推送节流是常态）；仍不行连 Xcode 看控制台 CloudKit 日志。
- Beta 审核被拒：按拒信调整（通常是缺隐私政策 URL 或截图），改完重提。
````

- [ ] **Step 2: 版本号 0.2.0**

`project.yml` 里 `MARKETING_VERSION: 0.1.0` 改为 `MARKETING_VERSION: 0.2.0`，然后：

Run: `./scripts/gen.sh && ./scripts/build.sh && ./scripts/test.sh`
Expected: 全部 ✅（最终门禁）。

- [ ] **Step 3: 提交**

```bash
git add docs/RELEASE.md project.yml
git commit -m "P2-T13 发布手册与版本 0.2.0：TestFlight 双轨分发、schema 生产部署、双机验收清单"
```

---

## 执行提示(SDD 控制器用)

- 模型选择：T1/T5/T9/T13 为转写型 → 最低档实现者；T2/T3/T6/T11/T12 中等；T4/T7/T8/T10 涉及多文件核对/UIKit 桥接 → 中档并给足 grep 指令。所有任务审查用中档，终局审查用最高档。
- T4/T7/T8/T9 含「以现有 DesignSystem 实际签名为准」的 grep 核对指令，实现者报告若称组件签名不符，属预期分支不是阻塞。
- CloudKit 网络路径（T6 ensureShare / T7 accept / T8 UI 触发）本质不可自动化验收，任务门禁只到构建+测试绿；端到端走 RELEASE.md 清单，由用户真机执行。
- 任务完成后测试计数预期：T2=45 → T3=47 → T5=49 → T6=51 → T9=52 → T10=55 → T11=60（供审查者核对有没有漏跑）。



