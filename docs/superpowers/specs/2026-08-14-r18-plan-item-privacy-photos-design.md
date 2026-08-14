# R18 · 单条日程私密 + 日程照片 设计稿

日期:2026-08-14 · 背景:R17 把「私密」做在了整趟见面上,用户澄清本意是**单条行前日程**可私密、**每条日程**可加照片。用户已定:1B(拆除整趟见面私密)/ 2A(私密日程见面开始不揭晓,转化成回忆那一刻自动公开)/ 3A(转化时照片带进回忆)。小样页 plan-item-privacy.html 四节用户已确认。

## 一、总决策

- 私密与照片的**粒度=CDPlanItem(行前日程)**;交互与小本本待办完全同款(私密→公开不可撤回;照片 9 张上限)。
- R17 的整趟见面私密 **UI 与过滤全部拆除**;CDMeeting 三字段与 MeetingRepository 的 reveal/start 自动公开**保留**(空转无害,兜住开发环境已产生的历史私密见面记录),对应单测保留。
- 备忘模式(day==nil 的轻记录)**不参与**私密与照片。

## 二、整趟见面私密拆除(1B)

1. `MeetingFormView`:私密开关段、脚注、确认弹窗、showsPrivacyToggle/visibilityLocked/visibility/confirmReveal/myID 相关代码全删;save() 恢复为不传 authorID/visibility(走仓库默认),edit 分支的 reveal 调用删除。
2. `MeetingsView`:visibleMeetings 计算属性与 myID 删除,各处(ForEach/空态/toolbar/批量删除)恢复直接用 `meetings`;plannedCard 的 MeetingPrivacyChip 删除。
3. `PlanView`:头部 chip 删除。
4. `HomeView.statusCard`:恢复 `let planned = try? repo.nextPlannedMeeting(couple:after:)` 原实现(函数仍在仓库);todayCard 的 meeting 级 `isVisible` 过滤移除(§三改为条目级过滤,myID 声明位置保留在 planRows 之前)。
5. `PlacesMapView.hasActivePlan`:meeting 级 `isVisible` 判断移除(§三改为条目级)。
6. 删除文件 `Features/Meetings/MeetingVisibility.swift`(CDMeeting.isVisible 扩展与 MeetingPrivacyChip 均无消费者)。
7. `DebugSeeder`:两条私密见面种子(演示惊喜/演示他方私密)删除,换 §六的日程级种子。
8. UI 测试 `testPrivatePlannedMeetingVisibility` 删除,由 §六新测试替代。
9. `Tests/MeetingPrivacyTests.swift` 保留不动(测的是保留的仓库 API)。

## 三、日程私密(2A)

### 模型与仓库
- **CDPlanItem 增 2 字段**:`visibilityRaw`(Int16 非空默认 0=sharedImmediately)、`revealedAt`(Date 可空)。authorPartnerID 已有。旧记录 0/nil=双方可见,行为不变。
- `PlanItemRepository` 增 `reveal(_ item:, at:)`(revealedAt 幂等置戳,同小本本语义);`add(...)` 增 `visibility: EntryVisibility = .sharedImmediately` 参数(尾部默认,既有调用零改动)。
- 可见性判定复用 `LedgerRules.isVisible(authorID:myID:visibilityRaw:revealedAt:)` 直调,不造扩展不造新函数(视图层过滤,与小本本/待办同构)。

### 表单(PlanItemFormSheet,仅日程模式)
- 「私密」开关段 + 脚注「开着=公开前只有你看得到 / 转化成回忆的那一刻会自动公开」,交互与 TodoFormView 同款:新建自由;编辑把私密关掉=弹「公开给 TA?」确认(确认后保存时 reveal);已公开锁定 disabled+「已公开,不可改回私密」。
- 备忘模式不渲染该段(切到备忘模式时不显示;备忘保存恒 sharedImmediately)。

### 公开时机(2A 语义,规则页 ④ 用户确认)
- 手动:表单关开关(上述)。
- 自动:**`.fromPlan` 转化成功的那一刻**——转化=建公开回忆+删日程源,私密条目随源删除消失、回忆双方可见,揭晓天然完成,无需显式 reveal 调用。
- **见面开始前勾完成不公开**(toggleDone 不碰可见性);见面开始时并入时间线不公开。

### 隐身面(对方侧 `!LedgerRules.isVisible` → 隐藏,实现时全仓 sweep `planItems` 遍历点)
1. `PlanView`(行前列表):sections 渲染处按条目过滤(含日期组与备忘组——备忘虽不可设私密,过滤口径统一挂上无害);
2. `TimelineListView`(见面中/结束后):散插待办卡、「接下来·还没做」组、「行前已备」划线卡、「没做成的计划」灰卡——全部条目级过滤;
3. `HomeView` 今天卡 planRows:条目级过滤(替代 R17 的 meeting 级);
4. `PlacesMapView.hasActivePlan`:条目级过滤(私密日程的地点不成计划钉,防钉子泄露——`LedgerRules.anyVisible` 先例);
5. **统计口径**:`PlanItemRepository.stats(for:)` 增 `visibleTo myID: UUID?` 参数(nil=全量),三个调用点(HomeView 倒计时「已安排 N 项」/PlanView 头部/MeetingsView plannedCard「行前计划 x/y」)全部传观看者 myID——TA 的计数不含你的私密项;
6. 提醒只响在设置它的手机上(既有机制,天然安全);日历/DaySheet 不画日程(既有事实);空间诊断计数不过滤(既有口径)。
- 行内标识:私密未公开条目在自己侧的行尾加「🔒」小字(PlanView 行与时间线待办卡,同待办行款)。

## 四、日程照片(3A)

- **模型**:`oneToMany(planItem, "evidences", evidence, "planItem")`——CDEvidence 第三个可选父关系(与 ledgerEntry/todoItem 互斥使用,删父级联删照片)。ManagedObjects 补 @NSManaged。
- `PlanItemRepository` 增 `evidencesSorted(_:)` / `addEvidences(_:datas:)` / `deleteEvidence(_:)`,照 TodoRepository 同款第三份(既有先例:不抽公共层)。
- `PlanItemFormSheet`(仅日程模式):「照片」栏,PhotosPicker 同款(max 9、52pt 缩略、evidencesToDelete 待删、onChange 加载),save 时删除/追加(savedItem 后)。备忘模式不渲染。
- `PlanItemDetailSheet`(查看页):照片区(110pt 横滑+EvidenceViewer 大图,同待办详情款),插在地点行之后备注之前。
- **转化带走**:`MomentFormView` `.fromPlan` 的 loadIfNeeded 预填 `photoDatas = evidencesSorted(item).compactMap(\.imageData)`——保存即成为回忆照片;转化删源级联删日程照片,不重复存两份。用户在补全表单里可继续增删,以最终表单为准。
- 行内缩略:PlanView 行/时间线待办卡行尾 22pt 首图缩略(有照片时,allowsHitTesting(false))。

## 五、备忘豁免

备忘(day==nil)不带私密与照片:表单备忘模式隐藏两段;备忘保存恒公开;MemoRow/侧签不变。备忘本就不进地图钉与今天卡,无过滤缺口。

## 六、测试与验收

- 单元:CDPlanItem 新字段 schema 断言(ModelSchemaTests 追加);PlanItemRepository reveal 幂等/evidence 增删排序/删父级联;stats(visibleTo:) 判定表(全量/我方视角/对方视角);add(visibility:) 默认与显式。
- UI(替代 R17 的 meeting 级测试):种子加**公开计划见面「演示行前」(南京,plannedStart 未来)** + 3 条日程:公开「取门票」/我方私密带一张照片「惊喜环节」/对方私密「演示他方私密项」。断言:行前列表见「惊喜环节」带 🔒 与缩略图、不见「演示他方私密项」;计划卡「行前计划 0/2」(可见口径);编辑「惊喜环节」表单私密开关存在且开。
- RELEASE.md:**验收 32-34 重写为日程口径**(32 私密日程对侧全隐:行前列表/时间线/今天卡/地图钉/计数;33 表单关私密确认→对侧出现→开关锁定;34 见面中转化成回忆→对侧立刻可见该回忆),35 追加「日程照片:表单加 9 张、查看页大图、转化后照片随回忆」;schema 部署行追加 CD_PlanItem 两字段与 CD_Evidence 的 CD_planItem 引用。
- 门禁与提交规矩同 R17(gen.sh/build.sh/test.sh/trailer)。

## 七、schema 部署(与 R17 合并为一次)

开发环境需再生成:CD_PlanItem.visibilityRaw/revealedAt、CD_Evidence 的 CD_planItem 引用(真机 debug 建一条私密带照片日程,再公开一次让 revealedAt 落值)。连同 R17 已生成的 CD_Meeting 三字段、CD_Evidence.CD_todoItem,**一次 Console Deploy**。构建 24 在部署后再打。

## 八、不做的事

- 备忘私密/照片;回忆(CDMoment)级私密;MeetingRepository/CDMeeting 字段回滚;私密日程的专门通知;诊断页计数过滤。
- 私密日程若从未转化、见面结束成灰卡:永远只在作者侧,无「事后揭晓」入口(编辑表单公开仍可用,足够)。
