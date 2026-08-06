# P4 小本本设计定稿（互评 / 喜怒 / 私密箱 / 公开流程）

日期：2026-08-06 ｜ 状态：**定稿**（用户逐项小样点选确认）
上位文档：`2026-07-29-anniversary-app-design.md`（主 spec）§5.4 / §6③④。本文与主 spec 冲突处以本文为准。
视觉小样：`.superpowers/brainstorm/81107-1785999684/content/`（gitignored，本地保留）。

## 一、范围

**本轮做**：
1. `LedgerRepository`（建 / 改 / 删 / 公开 / 过滤查询，TDD）
2. **小本本 tab 启用**（MainShell `disabledTab` → 真页面）+ 列表页（三段 chips + 筛选 chips）
3. **详情页**（全文 / 证据大图 / 公开给 TA 仪式钮 / 作者 ⋯ 菜单）
4. **互评完整表单**（一屏滚动，小样选 A）与**喜怒轻表单**（整页同构精简版，小样选 B），⊕ 面板两瓦片接线
5. **公开通知**：对方新记公开条目 / 私密转公开 → 本机轻通知（扩展既有 HistoryMonitor 管线）

**不做（明确出界）**：
- 正负数量统计报表（主 spec §5.4 既定，防比较焦虑）
- 「提醒一下」跨设备催评（P6 清单既有项）
- 私密条目的存储加密：私密 = **UI 级过滤**。技术事实：CloudKit 同步会把条目数据带到对方设备的本地库，仅靠双端 UI 不渲染保证不可见——自用情侣 App 可接受，写明留痕
- 喜怒条目的地点 / 事发日期字段（快捷语义：happenedAt = 记录时刻）

## 二、沿用的既有地基（P0 已建，零迁移）

- `CDLedgerEntry`（id / categoryRaw / authorPartnerID / title / detail / happenedAt / visibilityRaw / revealedAt / createdAt / couple / place / evidences）
- `CDEvidence`（id / imageData / thumbnailData / sortIndex / ledgerEntry）
- `LedgerCategory`：praise 0 积极 / complaint 1 消极 / like 2 喜欢 / trigger 3 雷区（raw 已锁死）
- `EntryVisibility`：sharedImmediately 0 / privateUntilRevealed 1
- 照片管线沿用记忆表单（PhotosPicker → Data → Thumbnailer 缩略）；地点选择复用 `PlacePickerSheet`（含归并 / 分类全套）

## 三、行为规则（用户定稿）

1. **改删权限**：只有作者能编辑 / 删除自己的条目；对方条目只读（同昵称锁哲学）。纯函数 `LedgerRules.canEdit(authorID:myID:) -> Bool`
2. **公开不可撤回**：`reveal` 置 `revealedAt`，一次性动作；已公开条目在编辑表单中可见性行锁定「公开」；后悔只能删除
3. **可见性判定**（纯函数 `LedgerRules.isVisible(entry:myID:)`）：我的条目恒可见；对方条目仅公开（sharedImmediately 或 revealedAt != nil）可见
4. **筛选语义**：全部 = 我可见的全集；TA 记的 = 作者为对方（天然只含公开）；我记的 = 作者为我（含私密，卡带 🔒）；私密箱 = 作者为我且未公开
5. **排序**：列表各段内按 `createdAt` 倒序（新记的在上）；卡片日期显示 `happenedAt`（互评的事发日期 / 喜怒的记录时刻）
6. **通知**：对方**新建公开条目**或**私密转公开** → 本机横幅「TA 记了一条小本本」（喜怒 / 互评不区分文案）；设置页新增开关行「TA 记了小本本」（`newLedgerAlertOn`，默认开），与「TA 记了新回忆」并列

## 四、列表页（小样选 A · 双行 chips）

- 导航题「小本本」；顶部两行：三段 chips（积极 / 消极 / 喜怒）+ 筛选 chips（全部 / TA 记的 / 我记的 / 私密箱），均 `SelectableChip` 同款语言
- **积极 / 消极段**：白卡列表——类别徽章（积极 = dsGreen 描边字；消极 = dsOrange 描边字）+ 标题 + 正文摘要 2 行 + meta 行（作者名 记 · M/d · 地点名）+ 首张证据缩略图（右下 26pt）+ 私密条目 🔒 角标
- **喜怒段**：段内分组「❤ 喜欢」/「⚡ 雷区」组头；卡片 = 左描边 3pt（喜欢 dsGreen / 雷区 dsOrange）+ 标题（一句话）+ 备注摘要（如有）+ meta 行；私密同款 🔒
- 空态：当前段与筛选组合为空时居中灰字「这一栏还是空的」
- 新增色板令牌：`DS.dsOrange = 0xFF9F0A`（警示 / 消极 / 雷区专用语义色，与 dsRed/dsGreen 同级；不作行动色）

## 五、详情页（小样选 A · 底部仪式钮）

- 系统导航栏 inline 标题 = 类别名；右上 ⋯ 菜单（**仅作者**）：编辑 / 删除（红色，居中 alert 确认「删除这条记录？」+ 删除 / 取消）
- 正文骨架：类别徽章 +（私密时）「🔒 仅自己可见」灰字 → 大标题 → meta「{作者} 记 · 事发 M 月 d 日 ·（地点名）」→ 全文 → 证据缩略行（点开全屏大图，复用 PhotoViewerView 管线）
- **公开给 TA**（仅 作者 = 我 且 私密）：底部整宽蓝钮「公开给 TA」+ 下方小字「公开后 TA 会收到轻通知，且不可撤回」；点击弹居中 alert：标题「公开给 TA？」正文「公开后 TA 会收到轻通知，且不可撤回。」按钮「公开」/「取消」
- 已公开的原私密条目：meta 行尾追加「· M/d 已公开」留痕小字
- 对方远端删除守卫沿用 PlanView 模式

## 六、互评表单（小样选 A · 一屏滚动，create/edit 双模式）

- sheet 呈现，标题「记一笔互评」/「编辑互评」；取消 / 保存 toolbar
- 字段顺序：类别双 chips（积极 / 消极，默认积极）→ 标题（单行，必填，占位「一句话概括」）→ 经过（多行，可选，占位「这件事的经过和你的感受…」）→ 证据照片（PhotosPicker 多张，编辑可增删，复用记忆表单交互）→ 事发日期（DatePicker .date，默认今天）→ 地点（复用 PlacePickerSheet，可跳过；已选可清除）→ 可见性（公开 / 🔒 私密 双 chips，默认公开）
- 表单底部脚注：「私密＝仅自己可见，之后可在详情页公开给 TA（不可撤回）」
- 保存门槛：标题非空；编辑模式预填现值；**编辑已公开条目：可见性行锁定「公开」**；编辑私密条目把可见性改为公开 = 等效公开动作（置 revealedAt，触发通知）

## 七、喜怒轻表单（小样选 B · 整页同构精简版）

- sheet 呈现，标题「记一条喜怒」；字段：类型双大卡（❤ 喜欢 / ⚡ 雷区，默认喜欢，选中色 dsGreen/dsOrange 描边）→ 一句话（单行，必填，占位「一句话说清楚，比如『吃完饭会自然牵手』」）→ 佐证照片（**最多 1 张**，要长篇大论去记互评）→ 备注（单行可选 → detail）→ 可见性（同六，默认公开）
- 数据映射：title = 一句话；detail = 备注；happenedAt = 保存时刻；place = nil
- 同款私密脚注；保存门槛：一句话非空

## 八、入口接线

- ⊕ 面板：「互评」瓦片 → 互评表单；「喜怒」瓦片 → 喜怒表单。**不依赖见面状态**（随时可记，与记忆 / 封盘的 ongoing 门槛无关）；couple 不存在时同面板既有兜底
- MainShell：`disabledTab("小本本")` → 真 tab（AppTab 加 case，NavigationStack 包列表页）
- 列表卡片点击 → 详情页（push）

## 九、通知实现口径

- 扩展 `HistoryMonitor` 的远端事务处理：识别 `CDLedgerEntry` 的插入（作者 = 对方 且 可见性 = 公开）与更新（作者 = 对方 且 revealedAt 从 nil 变非 nil）→ 发本地横幅「TA 记了一条小本本」
- 开关 `newLedgerAlertOn`（默认开）；设置页「通知」区加行「TA 记了小本本」，与既有「TA 记了新回忆」同款 Toggle
- 判定逻辑抽纯函数（可单测）；具体事务字段解析方式以 HistoryMonitor 既有 CDMoment 处理为模板，计划期定签名

## 十、边界与错误

- 私密条目在对方设备：数据在库、UI 恒不渲染（isVisible 过滤应用于列表 / 详情入口 / 通知判定三处）
- 证据图缺失 / 损坏：缩略位显示米灰占位；删除条目级联删证据（模型 cascade 已配）
- 保存失败沿用 `try?` + 既有错误提示模式；公开动作失败不置 revealedAt（可重试）
- 列表 FetchRequest 观察远端变更（对方新记 / 公开实时上屏），沿用 `let _ = count` 惯用法

## 十一、测试策略

- **TDD 纯函数 / 仓库**：`LedgerRules.canEdit / isVisible / 筛选谓词`（四档筛选 × 两种作者 × 两种可见性真值表）；`LedgerRepository.create / update / delete / reveal`（reveal 置时戳且不可逆——二次 reveal 不变时戳；delete 级联证据）；通知判定纯函数（插入 / 转公开 / 私密插入不报 / 自己的不报）
- UI 门禁：gen（新文件）+ build + 全量测试绿
- 设备清单（计划期落 RELEASE.md）：双机互记公开条目实时可见 + 通知横幅；私密条目对方完全不可见；转公开后对方可见 + 通知；雷区描边 / 私密箱筛选；编辑权限（对方条目无 ⋯ 菜单）；已公开条目编辑时可见性锁定
