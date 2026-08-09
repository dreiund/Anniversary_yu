# 反馈⑨轮设计定稿(备忘独立化 / 划掉即补全 / 日程查看+导航 / 小本本新壳)

> 定稿 2026-08-09。方案页答案:1A / 2A / 3A / 4B。类别映射为我方决策(用户图未覆盖「消极」):
> 「生气」tab = 消极(complaint)+ 雷区(trigger)两组;效果页验收时可再调。

## 一、备忘独立化(1A)

- `PlanItemFormSheet` 顶部加 segmented Picker「日程 | 备忘」:
  - **日程**:事项 / 时刻(**必填**,单行 DatePicker,彻底删掉「指定日期」Toggle)/ 地点 / 提醒 / 备注;
  - **备忘**:只有 事项 + 备注 两行。
  - 编辑时初始模式按 `item.day == nil` 判;可切换。**备忘模式保存**:day/time/remindAt 写 nil,
    原提醒同步取消;**place/placeText 保持原值不动**(表单无地点行=不触碰该字段——遗留
    「无日期+有地点」的旧数据不被静默清空,评审①裁定)。日程模式保存:day 与 time 写同一时刻值(R8 规则);
    旧全天数据(day 有 time 无)编辑时预填当日 09:00(R8 规则沿用)。数据零迁移:day==nil 即备忘。
- `PlanView` 备忘区:废弃 LazyVGrid 胶囊(adaptive 列把 chip 拉开=用户圈的间距问题),
  改 `GroupedSection` 紧凑列表行:圈(勾=toggleDone+勾掉取消提醒,现逻辑)+ 划线文字;
  contextMenu 编辑/删除保留;管理模式选择圈;左滑删对齐日程行(轻量 56pt 样式)。
- **见面开始后(ongoing/finished),备忘不进时间线卡流**(不做待办卡、不进「接下来」、不变灰卡):
  时间线滚动区**左缘竖排侧签「备忘 n」**(墨底白字,竖排文字,有备忘才显示,ongoing 与 finished 都在)。
  点击弹半屏 sheet(presentationDetents .medium):备忘列表行(同 PlanView 新样式,勾=纯划线记录,
  **永不转化**;左滑删)+ 底部「＋ 加备忘」(开表单锁备忘模式)。结束见面后侧签保留当存档,仍可勾可删。
- 时间线「＋ 加个待办」保留,开双模式表单(默认日程):存日程=散插待办卡;存备忘=进侧签弹窗。
- 「行前已备」组与灰卡从此只含**日程**(day != nil);已完成的备忘只在侧签里划线。

## 二、待办划掉 = 弹「补全这段回忆」表单(2A)

- `TimelineListView` 待办卡:**点圈与点卡同一动作** → `editingPlan = item`(打开 `.fromPlan` 预填表单);
  存储=转化成回忆+删计划+取消提醒(T4 既有语义);取消=圈不生效待办还在。删除 `convert(_:)` 秒转化直调。
- `PlanItemRepository.convertToMoment` 随之删除(唯一调用方消失,不留死码),其专属测试用例删除;
  **保留** `plannedMoment(of:)`(表单预填/排序仍用)与 `MomentType(placeCategory:)` 及其直接单测。
  字段映射的端到端保障转由 UI 用例承担(testRound8PlanFlow 改造,§五)。
- `PlanTodoCard` 圈的 accessibilityLabel 维持「划掉 <事项>」(测试兼容);行前已备划线卡逻辑不变。

## 三、行前日程:点击=查看页,地点可导航(3A)

- 新组件 `PlanItemDetailSheet(item:)`(只读 sheet):事项大标题 / 时刻行(月日周+时分,设了提醒加 ⏰)/
  地点卡(地名 + 蓝底「导航」胶囊按钮;点地名弹 PlaceMiniMapSheet)/ 备注段 / 作者小签。
  右上「编辑」→ 现 PlanItemFormSheet。入口:planned 态 `PlanView` 日程行点击(原直开编辑表单改此);
  备忘行点击仍是勾选;时间线待办卡不走查看(走§二表单)。
- **导航**:`MKMapItem(placemark: MKPlacemark(coordinate:))` + `name` + `openInMaps`(默认导航模式);
  仅坐标非零地点显示按钮。`PlaceMiniMapSheet` toolbar 同步加「导航」按钮(全 app 小地图统一受益)。

## 四、小本本新壳(4B:布局照用户图,配色米色纸感)

- 只换列表壳,**详情页/表单/LedgerRules/TodoRules/数据零改动**。
- 一级分段(白卡 tab,选中白底描边加粗、未选灰字):**好事**(praise)/ **生气**(complaint+trigger,
  组内小标题「记一笔」/「⚡雷区」)/ **喜好**(like)/ **待办**(记得做)。旧「喜怒」段与 ❤⚡ 分组样式、
  moodCard 左描边废弃。
- 头部重做:大标题「小本本」(取代 inline navigationTitle)+ 右侧「管理」白底描边圆角钮
  (从 toolbar 移入头部;批量删逻辑不变,仍只针对我的 entries)。
- 二级筛选:下划线 tab 样式(选中 actionBlue 下划线+字色):全部 / 我记录的 / TA记录的 / 私密
  (LedgerFilter 沿用);**待办段也显示此筛选**(按 authorPartnerID 口径),原「我做/Ta做」两组
  改平列表(TodoRules.sortKey 排序),行内脚注带「我做/Ta做」徽标。
- 卡片统一新样式:白底 + hairline 描边 + 大圆角(14),左侧圆底浅灰图标 + 右侧内容
  (标题 semibold / detail 灰字两行 / 脚注=作者·月日·地点(·🔒))。图标:好事 heart /
  记一笔 cloud.drizzle / 雷区 bolt / 喜好 star / 待办=现有勾选圈(行为不变,占图标位)。
  证据缩略图保留在脚注行尾。页面底色 DS.parchment,与全 App 米色纸感统一(4B)。

## 五、验证

- 单元:表单双模式保存字段(备忘全 nil+提醒取消 / 日程 day=time)、convertToMoment 删除后
  测试文件调整(留 plannedMoment 合成/类目映射用例)、既有 plannedFor 排序不动。
- UI:`testRound8PlanFlow` 改造(点圈 → 断言「补全这段回忆」弹出 → 存储 → 圈消失记忆卡在;
  种子备忘项断言从时间线组移到侧签弹窗);新 `testRound9Look`——行前备忘紧凑行截图 /
  时间线左缘侧签+弹窗截图 / 小本本四 tab 新卡截图(好事+待办两张)。全套回归绿。
