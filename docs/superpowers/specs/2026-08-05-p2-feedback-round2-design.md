# P2 试用反馈第二轮 · 设计（2026-08-05）

四条真机反馈：①无法解绑配对 ②双方信息只能创建者定义 ③计划见面不可改不可删 ④首页心情不区分作者。
版本 0.2.1、构建号 4（合并后统一改 project.yml）。视觉小样（会话期文件，五框）已获用户确认，本文为唯一权威。

## 背景事实（实现前必读）

- 数据物理上全部住在**创建方**的 iCloud：创建方私有库的共享 zone。受邀方只是经 CKShare 镜像到本机共享库 `Anniversary-shared.sqlite`。
- 身份判定：`CoupleRepository.isParticipantDevice(couple)` —— couple 所在 store 文件名是否为共享库。
- SharingManager 现有：`loadShare / ensureShare(遗留 share 补配置) / lockInvites(回滚) / accept`。
- SettingsView 现状：两侧昵称双方都可改；配对区按创建方/受邀方分叉。
- MeetingRepository 现状：只有 `createPlanned/start/end`，无 update/delete。
- 心情卡现状：`HomeView.moodCard` 两个 emoji 无标注；数据自带作者（`mood(couple:authorID:day:)`）。

## 一、解除配对（双向，同名入口）

两端设置页「配对与同步」组各出现一行红色「**解除配对**」，二次确认（confirmationDialog）后执行。语义：**结束配对但不删任何创建方数据**；受邀方端清空回引导页；复合 = 创建方重新「生成邀请」。

| 侧 | 显示条件 | 确认文案要点 | 底层动作 |
|---|---|---|---|
| 创建方 | `!isParticipantDevice && participantJoined` | 解除后 TA 的手机会清空这段空间并回引导页；你的记录全部保留；重新发邀请可恢复 | 把所有非 owner 参与者 `share.removeParticipant`，并 `publicPermission = .none`，一次 `persistUpdatedShare` 持久化；失败回滚本地修改并提示（沿用 lockInvites 的回滚纪律） |
| 受邀方 | `isParticipantDevice`（受邀方即已连接） | 解除后你的手机会清空这段空间并回引导页；TA 那边不受影响；想复合让 TA 重新发邀请 | `container.recordID(for: couple.objectID)?.zoneID` 取共享 zone，`purgeObjectsAndRecordsInZone(with:in: sharedStore)`（CloudKit 官方的"参与者退出共享"）；成功后本机共享库清空 → RootView 自动回引导页 |

**解绑后的创建方状态机（pairingStatus 修正）**——解绑后 share 仍存在（已锁、无参与者），现有 UI 会误显示「邀请已发出」+ 死链 ShareLink。规则表修正为：

| share 状态 | 状态文案 | 操作行 |
|---|---|---|
| nil | 未配对 | 生成邀请 |
| 有参与者已接受 | 已连接 | 发出邀请 + 锁定邀请（原逻辑不变） |
| 无参与者 && publicPermission ≠ .none | 邀请已发出 | 发出邀请（ShareLink） |
| 无参与者 && publicPermission == .none | 未配对 | 生成邀请（走既有"遗留 share 重开"分支，同链接复活） |

受邀方解绑的传播依赖 CloudKit 推送：创建方端「对方已加入」消失可能延迟数秒到数分钟（前台加速），属正常，不做超时兜底。创建方解绑同理反向。

不做（明确出圈）：创建方"退出/毁灭自己的空间"（等于删光全部回忆，不进设置页）；取消未被接受的邀请（锁定/重开已覆盖）。

## 二、昵称：严格各改各的（改动照常双向同步）

- **加入确认页（受邀方一次性）**：接受邀请、couple 出现在共享库后，进主界面前全屏展示：标题「欢迎加入我们的空间」、说明「TA 给你取的昵称是「X」，喜欢就确认，想改就改」、预填 TextField、主按钮「就用这个昵称」（文本去空格为空则禁用）、脚注「以后只有你自己能改它」。确认动作：`currentPartner(of:).name = 输入值` + 存库 + 置位 `@AppStorage("nameConfirmed-<coupleUUID>")` → 进 MainShell。
  - RootView 分支：`couple 存在 && isParticipantDevice && !flag` → 确认页；否则原逻辑。创建方设备永不出现此页。重装后 flag 丢失 → 再确认一次，可接受。
- **设置页锁定规则**：「TA 的昵称」在**已连接后**变只读展示（行尾 🔒、脚注「TA 的昵称由 TA 自己定」）；「我的昵称」始终可编辑。已连接 = 创建方 `participantJoined`、受邀方恒真。**未配对/邀请未被接受时创建方仍可改两个名字**（TA 本人还没进来，得能改错别字）。`save()` 相应只写有权的字段。
- 同步事实（回应用户提问）：昵称在共享数据上，任何一侧修改数秒内双向可见。本设计只限"谁有权改"，不改同步行为。
- 「在一起的日子」是 couple 级字段，不属于任何一人，维持双方可改，不在本轮变动。

## 三、见面：三态可改，删限计划中

- **编辑**（planned / ongoing / finished 都可）：
  - 入口：计划中 → PlanView 右上角「编辑」；进行中/已结束 → MeetingDetailView 右上角「编辑」。
  - 表单：复用 MeetingFormView 改造为 create/edit 双模式（沿用 MomentFormView 的模式先例），预填现值。
  - 字段按状态：planned → 标题/城市/plannedStart/plannedEnd；ongoing → 标题/城市/startedAt（结束日期行隐藏）；finished → 标题/城市/startedAt/endedAt。校验：结束 ≥ 开始（对应字段对）。
  - 仓库层 `update(meeting, title:city:start:end:)` 按状态写对应字段；只动元数据，**不触碰 dateDays/moments**（时间线分组挂在 dateDay 上，与见面日期编辑无关）。
- **删除**（仅 planned；ongoing/finished 永不提供删除）：
  - 表单底部红字「删除这次计划」→ confirmationDialog（说明连行前计划日程一起删）→ 仓库 `deletePlanned(meeting)`：先删其全部 CDPlanItem，再删 meeting（防 delete rule 不确定），guard 状态非 planned 时抛错。
  - **重编号**：删除后，其后所有见面（**不论状态**）`index -= 1`，序号保持连续——没发生过的计划被拿掉后，后面那次"第 N 次见面"在现实里确实该前移。纯函数化以便测试。
- HomeView 倒计时卡/足迹列表引用被删对象：均为 FetchRequest 驱动，删除即刷新，无需额外处理。

## 四、心情卡标名字

每个 emoji 正下方 10pt 小字标昵称；对应侧无记录时显示虚线圈（含"+"）同样带名字；保留行尾「还没打卡」提示（仅对方缺卡时）。点卡片行为不变（给自己打卡的 MoodSheet）。取名用 `currentPartner/otherPartner` 解析，与卡内 emoji 槽位一一对应。

## 测试与验收

- TDD 纯逻辑：重编号函数（中间删/末尾删/混合状态）、update 字段按状态落位、deletePlanned 状态门禁与级联、pairingStatus 四态规则表、昵称锁定条件（三种设备/连接组合）、加入确认页 gating 条件。
- CloudKit 动作（removeParticipant/purge）留在 SharingManager 薄层，参数拼装可测部分（zoneID 解析降级路径）单测，网络行为走真机。
- 真机验收补充（追加进 RELEASE.md §7）：13. 创建方解除配对 → 她端自动清空回引导页、你端变未配对；重新生成邀请（同链接）→ 她重走加入 → 恢复如初。14. 受邀方解除配对 → 反向同验。15. 她加入后出现改名确认页，改名后你端几秒内可见新名字。
- 版本：MARKETING_VERSION 0.2.1、CURRENT_PROJECT_VERSION 4；TestFlight 后续构建走既有流程（无重大更改，秒批为常态）。

## 出圈清单

创建方毁灭空间 / 删除进行中·已结束见面 / 取消未接受邀请 / 头像等昵称之外的"个人信息"（现阶段信息=昵称）/ 50m 地点归并（P3）/ 「提醒一下」定向催评（P6）。

---

## 修订 1（2026-08-07，反馈：开发期数据清理）

**「删限计划中」放开为任意状态可删**，覆盖第三节的删除条款与出圈清单中的「删除进行中·已结束见面」：

- 入口：足迹列表左滑「删除」（swipeActions），三种状态的卡都有；表单内红字「删除这次计划」仅计划中保留，走守卫入口 `deletePlanned`（guard 非 planned 抛错，语义不变）。
- 仓库层：新增通用 `delete(meeting)`——任意状态，约会日/记忆/照片/评价/行前日程按模型级联规则一并删除（亲密记录 nullify 解挂归 couple 保留）；重编号规则沿用（其后所有见面 index -= 1）。`deletePlanned` 改为守卫后委托 `delete`。
- 确认弹窗按状态措辞：计划中「删除这次计划？/行前计划的日程会一起删除。」；进行中/已结束「删除这次见面？/这次见面的所有约会日、记忆和照片会一并删除，无法恢复。」
- 动机：开发测试期清理瞎建数据。删除经 CloudKit 同步双端生效，弹窗即防线。

## 修订 2（2026-08-07，反馈：左滑删除推广 + 批量管理 + 封盘可删）

- **左滑删除推广到子列表**（复用 SwipeDeleteRow 同观感）：
  - 时间线记忆卡 → 确认弹窗「删除这条记忆？/这条记忆和它的照片、评价会一并删除」；
  - 时间线封盘卡 → 删这一天（CDDateDay）：**仅空天可删**，还有记忆时弹「还不能删除/这一天还有 n 条记忆，先删掉记忆再删封盘。」（用户定稿）；删后天序号前移。删记忆有意不自动清空天，流程即「删光记忆 → 再滑删封盘」；
  - 行前计划日程行 → 行内紧凑样式（56pt 图标钮、即删不弹窗，与备忘 chip 长按删除同级）；
  - 小本本条目（积极/消极/喜怒）→ 仅作者的条目可滑（canEdit），确认弹窗同详情页。
- **批量管理（用户选各列表内「管理」模式）**：足迹列表/时间线/行前计划/小本本四处右上角「管理」→ 选择圈勾选 → 底栏「已选 n 项 · 删除所选（红字）」→ 确认弹窗 → 批量删。小本本管理模式下对方条目淡显不可选；时间线封盘卡不参与勾选（滑删专属）。
- 仓库层：deleteDay（守卫 dayNotEmpty）、四仓库数组重载 delete(_:)（单次保存），见面批量删后统一重排序号（renumberMeetings）。
- 组件：SwipeDeleteRow 参数化（宽度/圆角/内缩/仅图标）；关闭态删除按钮整个移出视图树（透明按钮残留无障碍树，多行时 VoiceOver/UI 测试撞隐形按钮）。

## 修订 3（2026-08-07，反馈：进行中要能改结束日期）

第三节「ongoing → 仅 startedAt（结束日期行隐藏）」放开：**进行中编辑 = 实际开始 + 预计结束（plannedEnd）**。
还没结束确实没有 endedAt，但行程延后时要能改「预计结束」——足迹列表卡的日期范围显示的正是
`endedAt ?? plannedEnd`。仓库层 update 的 ongoing 分支同步写 plannedEnd；已结束仍编辑实际结束（endedAt）。
