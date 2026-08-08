# 反馈⑥轮功能设计定稿（排卵预测 · 记得做 · 今天卡 · 本地提醒 · 可见性开关统一 · 足迹日历滑动）

> 定稿 2026-08-08。方案页四问答案：1A（排卵期 10 天）、2A（记得做带完成勾选，⊕ 格子名「记得做」）
> +追加「公开/私密改开关并统一到喜怒/互评」、3A（独立深色今天卡）、4A（本地通知提醒）。
> 同轮已修 bug 三件（点选二次不亮/亲密可编辑时刻/孤儿地点清理，4f5083e）不在本文范围。
> **schema 变更**：本轮新增 CDTodoItem 实体 + CDPlanItem.remindAt 字段，需一次 CloudKit
> 增量部署（§七）；这是 P5「不新增字段」约束的正式解除。

## 一、排卵期 / 排卵日预测（1A）

- 算法（CyclePredictor 扩展，纯函数）：**排卵日 = 「下一次经期开始日」− 14 天；排卵期 =
  排卵日前 5 天 … 后 4 天（共 10 天，美柚口径）**。
  - 「下一次开始日」取值：未来 = 预测开始日（现有 nextStarts 三个都算）；
    历史 = 相邻两段实际周期中后一段的实际开始日（历史区间也回填紫窗，供回看）。
  - 数据积累中（完整周期 < 2，缺省 28/7）时照常显示，图例注明。
- 渲染（她月历 + 足迹日历一致）：
  - 排卵期天 = **淡紫底 `DS.ovulationBg #F0E6FA` + 紫字 `DS.ovulationInk #8E44AD`**（DS 新增两色）；
  - 排卵日 = 数字下加 `🌸` 下标（替代该日的四点行位置之上，四点照常显示在 🌸 下方；
    足迹日历无四点，🌸 直接放数字下）；
  - 优先级：经期红底 > 排卵紫底 > 白底；今天墨环、预测虚线照旧（虚线预测天与紫窗按定义不相交）。
  - 她月历图例第一行追加 `· 紫=排卵期`；🌸 无需图例（点睛自明）。
- 足迹日历：紫底与经期浅粉底同受设置开关控制，开关改名 `足迹日历周期底色`（键
  `footprintsCycleTintOn` 不变，老用户设置保留）。

## 二、小本本第四段「记得做」（2A）

### 数据（新实体 CDTodoItem，见 §七部署）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | UUID | |
| title | String | 事项主题（通知标题用它） |
| detail | String? | 详情 |
| dueAt | Date? | 目标日（日粒度，startOfDay） |
| assigneePartnerID | UUID | **归谁做**——渲染视角的依据 |
| authorPartnerID | UUID | 作者（编辑/删除权、私密可见性判定） |
| visibilityRaw | Int16 | 复用 EntryVisibility 锁值（0 公开 / 1 私密） |
| revealedAt | Date? | 公开仪式时戳（一次性，复用小本本语义） |
| isDone | Bool =false | 完成勾选 |
| doneAt | Date? | 完成时刻 |
| remindAt | Date? | 提醒时刻（nil=关，见 §五） |
| createdAt | Date | |
| place → CDPlace? | 关系 | nullify；couple → cascade 归属 |

### 规则（TodoRules 纯函数，TDD）

- 可见性与小本本同构：`isVisible`＝自己的恒可见；对方的仅公开（visibilityRaw==0 或 revealedAt≠nil）可见。
- **视角渲染**：我的列表「📌 我做」＝assignee==我 且可见；「👉 Ta做」＝assignee==对方 且可见。
  你记的「Ta做」公开条目（assignee=她）→ 她那边出现在「我做」组；反之对称。私密条目公开前只在作者端可见（带 🔒）。
- 权限：编辑/删除＝仅作者；**完成勾选＝作者或 assignee 都可**（共管勾选）；私密转公开＝作者的一次性仪式（沿用 reveal 语义）。
- 排序：未完成在前按 dueAt 升序（nil 最后），已完成沉组尾按 doneAt 降序、划线灰显。

### 表单（TodoFormView，create/edit 双模式）

- 顶部分段 `Ta做 | 我做`（默认 Ta做）→ 决定 assigneePartnerID（Ta做=对方，我做=自己）。
- 字段：标题（必填）、详情（可选）、`目标日` DatePicker（date，默认今天、总是落值——schema 里可空仅为容错）、
  地点（PlacePickerSheet 复用，可选）、`私密` Toggle（见 §三）、`提醒我` 行（见 §五）。
- 保存钮 `保存`；编辑模式底部红字 `删除这条`（确认弹窗 `删除这条记得做？`）。

### 列表（小本本第四段）

- 段 chips 变四个：`积极 消极 喜怒 记得做`；**记得做段不套四档筛选**（有自己的 我做/Ta做 分组），
  筛选行在该段隐藏。
- 组头 `📌 我做` / `👉 Ta做`（同喜怒段组头样式）；行＝圆圈勾选钮（点击切 isDone，行动蓝实心✓=已完成，
  已完成标题划线灰显沉组尾）+ 标题 + footnote（`M月d日`（dueAt）· 🔒（私密）· `已完成`）。
- 行点击（勾选钮以外区域）→ 作者进编辑表单；非作者进只读详情 sheet（字段全览 +
  assignee 的大号 `完成` / `取消完成` 钮）。行左滑删除＝仅作者条目可滑（SwipeDeleteRow，确认弹窗同表单）。
- 私密条目的公开入口：编辑表单内 `私密` Toggle 关掉即等效公开仪式（确认弹窗
  `公开给 TA？` / `公开后 TA 会看到这条，且不可撤回。`——与小本本锁定语义一致，公开后 Toggle 置灰）。

### ⊕ 面板

- 第 5 格 `亲密` 替换为 `记得做`（SF `checkmark.circle`）→ 打开 TodoFormView（create）。
  亲密此后只从她页日历点日进入（用户定稿）。

### 通知（不做项）

- 新条目/公开不推横幅（区别于小本本——记得做有「今天卡」和列表承接，避免通知噪音）；后续要再加。

## 三、公开/私密统一改开关（用户追加）

- 三处表单（互评 LedgerFormView、喜怒 QuickLedgerSheet、记得做 TodoFormView）的可见性控件统一为
  **Toggle `私密`**：开=仅自己可见（privateUntilRevealed），关=公开（sharedImmediately）。默认关（公开）。
- 附注小字（Toggle 下方 footnote）：`开着=公开前只有你看得到`。
- 锁定态（条目已公开——sharedImmediately 或 revealedAt≠nil 的编辑模式）：Toggle 强制关+置灰，
  小字换 `已公开，不可改回私密`（沿用 P4 锁定语义，等效 reveal 路径保留：私密条目编辑中把 Toggle 关掉
  = 公开仪式，弹确认）。
- 原 chips 样式删除；raw 锁值与 LedgerRules/仓库逻辑零改动（纯控件替换）。

## 四、「我们」页 · 今天卡（3A）

- 位置：提醒区上方，独立 **DarkCard**；无任何事项时整卡不渲染。
- 标题行：`今天 · M月d日 EEE`（小字 onDarkMuted）。
- 行（皆白字 15pt + 行尾 skyBlue 小链接，行序固定）：
  1. **今天的行前日程**（进行中或计划中见面的 planItems，day==今天，按时间升序，最多 3 条溢出
     `还有 n 条`）：`🕐 HH:mm 标题`（time nil → `全天 标题`），链接 `行前 ›` → push PlanView(该见面)。
  2. **经期状态**（与首页提醒区现行判定同源，两行互斥）：`🩷 经期第 n 天` 或 `🕐 已推迟 n 天`，
     链接 `她 ›` → push HerView。（该行加入后，提醒区里的同信息行**移除**，不重复出现。）
  3. **今天到期的记得做**（dueAt==今天 且未完成且可见，我做+Ta做都列，前缀 📌/👉）：`📌 标题`，
     链接 `记得做 ›` → push LedgerListView(initialSegment: .todos)。
- LedgerListView 增加 `initialSegment` 参数（默认 .praise，不影响 tab 入口）。

## 五、本地通知提醒（4A；覆盖 记得做 + 行前日程）

- **能力边界（定稿共识）**：iOS 第三方无法写系统闹钟/跳转时钟 App（AlarmKit 仅 iOS 26+，
  她机 17.3.1 不可用）——用 UNUserNotificationCenter 本地通知实现。
- 字段:CDTodoItem.remindAt（§二）；**CDPlanItem 增量新增 remindAt: Date?**（§七部署）。
- 表单 UI（TodoFormView 与 PlanItemFormSheet 一致）：`提醒我` Toggle + 展开 `提醒时刻`
  DatePicker（date+time；默认＝目标日/日程日 09:00）。
- 排程规则：**通知在操作发生的设备上排/取消**（字段随 CloudKit 同步、对方设备可见但不响铃；
  换机重装后需重新开一次提醒——两人 App 可接受，写进小字：`提醒只响在设置它的手机上`）。
  - 排：保存且 remindAt≠nil 且未来 → UNCalendarNotificationTrigger，id `todo-<uuid>` / `plan-<uuid>`，
    title=事项标题，body=`记得做` / `行前日程`（detail 非空则用 detail），声音默认。
  - 取消：关 Toggle / 删除条目 / 记得做勾选完成 → removePendingNotificationRequests(该 id)。
  - 改时刻：先取消再重排（同 id 覆盖即可）。
- 权限：沿用既有 requestAuthorization 管线（LocalNotifier 同款请求）。

## 六、足迹日历滑动切换（无分歧项）

- CalendarView 月份切换改 **TabView(.page) 左右滑动**，与她页月历同构（月偏移 -24…12、
  `回今天`、既有 ‹ › 步进钮保留并与滑动同步）；自然日/约会日投影、格内容、点天抽屉零改动。

## 七、CloudKit schema 增量部署（一次性步骤，随实现计划执行）

1. ModelSchema 增 CDTodoItem 实体（§二字段+关系：couple→todos cascade、place→todoItems nullify）
   与 CDPlanItem.remindAt 属性；ManagedObjects 同步。
2. 跑一次 `-InitCloudKitSchema`（Development）→ CloudKit Console Deploy Schema Changes… 到
   Production（RELEASE.md §一同款步骤，增量、老数据不动）。
3. 部署完成前 TestFlight 旧构建照常工作（新字段/实体旧端不认识即忽略）。

## 八、测试与验收

- 单元：CyclePredictor 排卵窗矩阵（未来 3 窗/历史回填/缺省期/红紫优先级归 view 不测）；
  TodoRules（可见性/视角分组/权限/排序）；TodoRepository CRUD+勾选+reveal 等效；
  提醒排程纯函数化可测部分（id 构造/触发时刻组装）；PlanItem remindAt 读写。
- UI 截图：她月历紫窗+🌸、小本本记得做段、今天卡、表单开关态；种子补排卵可见的周期与两条记得做。
- 双机：你记「Ta做」公开 → 她端「我做」出现并可勾选；勾选双向同步；私密→公开仪式；提醒只响本机。

## 出圈清单（本轮不做）

记得做新条目/公开的推送横幅 · 提醒的跨设备镜像 · 排卵科学化参数（黄体期自定义）· 今天卡自定义行序 ·
系统闹钟/AlarmKit（P6+ 视 iOS 26 普及再议）。
