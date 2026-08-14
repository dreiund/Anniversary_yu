# R17 · 小本本契合度三改 + 完成开关渲染修 设计稿

日期:2026-08-14 · 已与用户确认:1A(推入式待办详情)、2A(行内导航药丸)、3A(私密只用表单开关);§四规则条款用户已过目无异议。

## 一、背景与目标

小本本四段(好事/生气/喜好/待办)交互不契合:前三段点条目先进浏览详情,待办却直接进编辑;详情页地点只是灰字无法导航;计划见面没有私密选项(想做惊喜)。另有用户报告的老 bug:待办完成开关点按后界面时常不刷新(数据实际已变)。

本轮四件事:
1. **待办点按统一为「先看详情」**(和好事同款推入式),待办加照片(同证据照片机制,最多 9 张);
2. **详情页地点行一键导航**(好事/生气/喜好/待办详情,同行前日程查看页模式);
3. **计划见面加「私密」**(复用小本本「私密→公开不可撤回」机制,开始见面自动公开);
4. **待办完成开关渲染 bug 根修**(R12 MemoRow 同族,行级 @ObservedObject)。

## 二、待办详情页统一(1A)

### 行为
- 小本本待办段点行(作者与非作者一致)→ NavigationLink **推入** `TodoDetailView`(新文件 `Features/Ledger/TodoDetailView.swift`);旧 `TodoDetailSheet`(LedgerListView 内私有 struct)删除。全仓唯一浏览入口(首页今天卡待办行仍跳列表,不直跳详情,不动)。
- 行内勾选圈行为不变(直接完成/取消完成);作者左滑删除、管理模式批量选均不变。
- 编辑入口后移:详情页右上「⋯」菜单(仅作者可见)→ 编辑(sheet 弹 `TodoFormView(mode: .edit)`)/删除(确认弹窗,删除后取消提醒、退场)。

### TodoDetailView 版式(照 LedgerDetailView 同款)
- 主体卡 ParchmentCard:徽章「待办 · 我做/Ta做」(actionBlue 系,按 assigneePartnerID==myID 判)+ 右上「🔒 仅自己可见」(未公开时)+ 标题 + 详情文字。
- 信息行 GroupedSection:记录人 / 目标日(无=「—」)/ 提醒(remindAt 有值时显示,zh 格式)/ 可见性(同 LedgerDetailView 三态文案)/ 完成态(已完成 dsGreen / 未完成 inkMuted)。
- 地点行:§三样式(有 place 才显示)。
- 照片区:同 LedgerDetailView「证据」区结构,标题用「照片」,横滑 110pt 缩略图,点开全屏(复用 `EvidenceViewer`:去掉 private 提为 internal,留在 LedgerDetailView.swift 原文件,不重复实现)。
- 底部 safeAreaInset:`canToggleDone` 者见「完成/取消完成」蓝药丸(完成时取消提醒,同现有逻辑)。私密公开仍走表单开关(待办既有机制),详情页**不加**「公开给 TA」钮——底部只留一个主操作。
- 守卫:`@ObservedObject var todo` + `managedObjectContext == nil || isDeleted` 早退(P6 F-2 同款)。

### 照片(数据层)
- **模型增量**:`oneToMany(todo, "evidences", evidence, "todoItem")`——CDEvidence 增第二个可选父关系 todoItem(与 ledgerEntry 互斥使用,删父级联删照片)。ManagedObjects 补对应 @NSManaged 属性。
- TodoRepository 增 `evidencesSorted(_:)` / `addEvidence(_:imageData:thumbnailData:)` / `deleteEvidence(_:)`,照 LedgerRepository 同款实现(不强行抽公共层)。
- `TodoFormView` 加「照片」栏:PhotosPicker 同 LedgerFormView(max 9、缩略图横排、待删标记 evidencesToDelete、保存时统一落库/删除;压缩与缩略图生成沿用 LedgerFormView 现成管线)。
- 列表 todoRow 的 meta 行尾加 26pt 首图缩略(有照片时),同 newCard。

## 三、详情页地点导航(2A)

- `SmallBluePillButtonStyle` 从 PlanItemDetailSheet 的 private 提为共享(挪进 DesignSystem/DSButtons.swift),行前日程查看页改用共享版。
- LedgerDetailView:地点信息行从 GroupedRow 灰字改为独立地点行(同 PlanItemDetailSheet):`📍 地点名`(actionBlue,坐标非零时可点 → PlaceMiniMapSheet)+ 右侧「导航」小药丸(坐标非零才显示 → `openInMapsNavigation(place:)`,高德优先退苹果地图)。无坐标(手填纯文字地点,lat/lon 均为 0):只显示灰字名字,无导航钮、不可点。
- TodoDetailView(§二新页)同款地点行。
- 范围就这四段详情 + 行前日程(已有);MomentDetailView 等不在本轮。

## 四、私密计划见面(3A)

### 模型与仓库
- **CDMeeting 增 3 字段**:`authorPartnerID`(UUID 可空)、`visibilityRaw`(Int16 非空默认 0=sharedImmediately)、`revealedAt`(Date 可空)。旧记录 nil/0 → 双方可见,行为不变。
- `MeetingRepository.createPlanned` 增 `authorID:` `visibility:` 参数;新增 `reveal(_ meeting:, at:)`(置 revealedAt,幂等);`start(_:at:)` 内:若 `!LedgerRules.isRevealed(...)` 先 reveal 再置 ongoing(**开始见面=自动公开**,单点收口)。
- 可见性判定复用 `LedgerRules.isVisible(authorID:myID:visibilityRaw:revealedAt:)`,不再造函数。

### 表单(MeetingFormView)
- 「私密」开关段 + 脚注,交互与 TodoFormView 完全同款:新建自由切换;编辑时把私密关掉 = 弹「公开给 TA?」确认(确认后保存时调 reveal);已公开锁定 disabled + 脚注「已公开,不可改回私密」。
- 开关仅在 status==planned 且(新建 或 我是作者)时显示;非 planned、非作者、旧数据(authorPartnerID 为 nil 视为已公开)不显示。
- 新建保存:authorID=myID、visibility=开关值。

### 过滤面(对方侧 !isVisible → 隐藏)
实现时以全仓 sweep 为准(检索 `MeetingStatus.planned` 取用点与 `planItems` 遍历点),已知清单:
1. `MeetingsView` 列表(计划卡不出现;批量管理同口径);
2. `HomeView`:planned 倒计时的选取处;今天卡 planRows(父见面不可见 → 其行前计划行全部不出);
3. `CalendarView`/`CalendarProjector`:CalMeetingInput 构造处过滤(不可见见面不画色带/不计 summary);`DaySheet` 同口径;
4. `PlacesMapView`:`hasActivePlan`(place.planItems 判定)与「计划」「待办」类目、地点抽屉/档案页里列 planItems 处——父见面不可见的 planItem 一律不算不显(同 `LedgerRules.anyVisible` 防钉子泄露先例);
5. 提醒本地机制不受影响(只响在设置它的手机上);CoupleDiagnosticsView 计数**不过滤**(诊断页是本机数据视角,不做)。

### 可见侧标识
- plannedCard(自己看):右上「🔒 私密」琥珀 chip(F5E3C2 底/8A5A00 字系,深色模式用动态色)。
- PlanView 头部:私密未公开时标题旁加同款小 chip(作者自己知道这单还没公开)。

### 定死的规则(用户已确认)
- 开始见面=自动公开,公开后不可回私密;
- 信任模型与小本本私密一致:数据同步到对方设备,仅 UI 隐藏;
- 编号怪癖接受:私密「第 5 次」存在时对方新计划显示「第 6 次」,公开后自然补齐;
- 见面公开不做专门通知(自然出现),1.0.x 台账;
- 双端需同构建;发 TestFlight 前需 CloudKit Console 再部署一次 schema。

## 五、待办完成开关渲染 bug(随轮根修)

- 症状:小本本待办段点勾选圈,界面时常不刷新(圈不变/不划线),数据实际已变(重进页面显示已完成)。老问题。
- 诊断方向(R12 MemoRow 同族):`todoRow` 是父视图内联 builder,行不以 @ObservedObject 订阅对象级变更;待办列表来自 repo 命令式查询,仅靠 `todoItems.count` 注册依赖,isDone 翻转不改 count,刷新时机不受控。
- 修法:抽私有 `TodoRow` struct + `@ObservedObject var todo: CDTodoItem`(圈图标/删除线/meta 全部行内取值),父视图只传对象。**先写失败测试**:UI 回归——种子待办 → 点圈 → 断言删除线/图标翻转 → 再点 → 断言恢复(双击回归,R12 同款断言法);若 LazyVStack 下无法稳定复现失败,以结构性同修落地并保留该回归测试。

## 六、测试与验收

- 单元:TodoRepository 照片增删/排序;MeetingRepository createPlanned 带作者与可见性、reveal 幂等、start 自动公开;CalendarProjector 过滤后输入不画私密见面;LedgerRules.isVisible 用于 meeting 口径的判定表(作者可见/对方不可见/公开后双方可见/旧数据 nil 视为公开)。
- UI:待办点行进详情(作者与非作者同路)、详情「⋯」编辑入口、完成钮翻转;详情地点行导航钮出现条件(有/无坐标);私密计划:创建带🔒chip、开始见面后 chip 消失;§五双击回归。
- 门禁:`./scripts/build.sh` / `./scripts/test.sh` 全绿;新 .swift 文件先 `./scripts/gen.sh`。
- RELEASE.md:验收清单追加「私密计划双机验收」(A 建私密→B 全面不可见:列表/倒计时/日历/地图;A 公开或开始见面→B 出现);schema 部署步骤追加本轮字段。

## 七、CloudKit schema 部署(上线动作)

新增:CDMeeting.authorPartnerID / visibilityRaw / revealedAt 三字段,CDEvidence 的 todoItem 关系(CD_todoItem 引用字段)。开发环境跑一次真机同步生成 schema → Console「Deploy Schema Changes to Production」。发 TestFlight 前完成,老流程照 docs/RELEASE.md。

## 八、不做的事

- 待办详情不加「公开给 TA」仪式钮(公开仍走表单开关);
- 见面公开通知、MomentDetailView 导航、诊断页计数过滤:不做/1.0.x;
- 不动 reveal 既有轻通知机制与 HistoryMonitor。
