# P6 打磨设计定稿(健壮性必修 + 命名统一;上架素材另行)

> 定稿 2026-08-09。范围=用户确认的 A+B+C 中的工程部分(B 健壮性 + C 统一);
> A(图标/商店素材/ASC 元数据)走设计线另行推进。D 类(跨设备催评/封盘时刻改期等)推 1.0.x。
> ⚠️ 本轮含 **CloudKit schema 增量**(CDCycle.authorPartnerID)——上传新构建前必须按 RELEASE.md 部署。

## 一、B 健壮性必修

### B1 双 couple 歧义防线(P2 真实事故:女友自建空间+受邀并存→随机串台)
- `CoupleRepository.fetchCouple()` 确定性化:多 couple 并存时**优先共享 store 里的**(配对完成的
  语义强),同 store 内按 createdAt 最早;不再依赖无排序 fetch 的随机首个。
- 接受邀请成功的收尾处:若本地私有 store 存在「空单人 couple」(只有一个 partner 且名下零
  moments/meetings/entries/todos/cycles),自动删除并记 log——事故场景自动自愈。
- 设置页配对区:检测到 >1 couple 时显示警示行「检测到重复空间 · 联系开发者」(私人 App,
  提示到位即可,不做复杂 UI)。

### B2 经期通知第二设备误报(P5 挂账)
- **schema 增量**:`CDCycle` 加 `authorPartnerID: UUID?`(可选,旧数据 nil)。
- 写入点:cycle 创建/补录时写当前 partnerID。
- `HistoryMonitor` 的 cycle 插入通知过滤加二级条件:`authorPartnerID != myID` 才响
  (nil 视为响,兼容旧数据不静默)。
- RELEASE.md 记增量部署步骤(1 字段)。

### B3 已勾事项编辑保存复活提醒(R9 复审发现,Plan/Todo 两侧同修)
- `PlanItemFormSheet.save()` 与 `TodoFormView.save()`:调度提醒前检查 `isDone`——已完成项
  保存时无条件 cancel、不 schedule(注释说明:完成的事项不该再响)。

### B4 配对 accept 失败用户文案(P2 挂账)
- CKShare 接受失败路径(delegate 与引导页两处)弹 alert:「接受邀请失败 · 检查网络后重试,
  或让对方重新发一次邀请」;不再静默。

### B5 前台通知不显示(P2 挂账)
- 实现 `UNUserNotificationCenterDelegate.willPresent` 返回 `[.banner, .sound]`,App 在前台时
  本地通知(封盘/记得做/日程/经期/TA 新记)也可见;delegate 挂 App 启动处。

## 二、C 命名与文案统一

### C1 小本本词表统一(R9 改名后的漂移)
- ⊕ 面板「喜怒」格 → 拆分或改名与四 tab 一致(实现时看面板格位:优先改成「喜好」「生气」
  两格;格位不够则一格「喜好/生气」点开表单内选)。
- 「记得做」→「待办」:⊕ 面板格、TodoFormView 标题、今天卡行文案、足迹地图 chip、
  相关 alert 文案全部统一为「待办」;通知 body「记得做」同步。
- 计划提醒通知 body「行前日程」→「日程」。

### C2 保存动词统一(P1 挂账)
- 全仓表单确认按钮统一为「保存」(现「存储/保存」混用);grep 全部 toolbar 确认钮改齐。

### C3 交互补齐
- 备忘行正文点击=勾选(PlanView.memoRow 与 MemoRow 两处加整行 tap→toggle,圈保留)。
- `hasActivePlan` 排除备忘(`day != nil` 才计入「计」钉——备忘已独立出计划流水线,
  不该在地图出钉;R9 终审 M-1 裁定落地)。

### C4 微清理(顺手,不扩散)
- LedgerListView 四处 `cornerRadius: 14` → `DS.Radius.darkCard`;entriesSection 图标三目加注释。
- MeetingDetailView 的 `meeting` 改 `@ObservedObject`(R8 M-4:对方结束见面即时刷 chips)。

## 三、A 工程侧配套(与素材线汇合时做)
- 版本号推 1.0.0(构建号顺延);`ITSAppUsesNonExemptEncryption: false` 进 project.yml 的
  Info.plist 段(标准加密免申报)。
- 图标选定后:1024 成品 → Asset Catalog 全尺寸;商店截图套装(模拟器截图+文案框)。

## 四、验证
- 单元:fetchCouple 确定性(双 couple 场景选共享 store/最早);空 couple 自愈判定(有数据不删);
  cycle 通知二级过滤(自己记的不响/对方记的响/旧数据 nil 响);提醒复活回归(已勾项保存后
  无 pending 通知)。
- UI:全套既有用例通过(文案改动同步断言:「记得做」→「待办」等);今天卡/⊕面板截图人工核词表。
- 双机验收清单补三条:前台通知可见/配对失败提示/对方结束见面本机 chips 即时变化。

## 五、已知边界(用户 2026-08-09 裁定)

- **并发编辑=后写者胜(接受)**:两人同时编辑同一条记录(回忆/备忘等),后同步者整记录覆盖先写者,
  无提示——CloudKit 记录级 LWW,不会崩溃/串数据/损坏,损失上限=一次编辑内容。天然安全面:互评各自
  记录、小本本/待办作者独有编辑权、同勾收敛、删除竞态表单守卫。**1.0.x 计划**:主要实体加 modifiedAt
  +保存时冲突提示「TA 刚改过这条」(schema 增量,与未来字段部署合并操作)。
