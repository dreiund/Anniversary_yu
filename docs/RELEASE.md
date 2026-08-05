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
3. TestFlight 外部测试要求填「Beta 版 App 信息」：反馈邮箱填你的邮箱；隐私政策 URL 必填——**已上线：`https://dreiund.github.io/anniversary-privacy/`**（仓库 dreiund/anniversary-privacy，2026-08-03 建）。

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
13. 解除配对（创建方发起）：你端设置点「解除配对」→ 确认 → 状态变未配对；她端 App 放前台等一会儿自动清空回引导页。你端再点「生成邀请」（同链接复活）→ 她重走加入 → 恢复如初。
14. 解除配对（受邀方发起）：反向同验——她端点「解除配对」→ 本机清空回引导页；你端「配对状态」恢复未配对、可重新邀请。
15. 加入确认页：她接受邀请后先见「欢迎加入我们的空间」，确认/修改昵称后进主界面；改名几秒内你端可见；你端设置里她的昵称行变只读带锁。

## 八、故障速查

- 「同步已暂停」横幅：设备没登录 iCloud 或 iCloud Drive 关闭 → 设置里登录/打开后自动恢复。
- 她点链接没反应：确认她已先装 App（链接要由 App 接）；App 已装仍不行 → 卸载重装后再点链接。
- 两端数据长时间不一致：双方都打开 App 放前台一分钟（静默推送节流是常态）；仍不行连 Xcode 看控制台 CloudKit 日志。
- Beta 审核被拒：按拒信调整（通常是缺隐私政策 URL 或截图），改完重提。
