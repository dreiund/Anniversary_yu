import XCTest

/// 地图筛选切空类目的复现脚本：种子数据只有 美食/景点公园 两类，切「出行」应清空钉位。
/// (反馈⑬③:咖啡甜品并入美食不再单列,空类目改用新增的「出行」)
/// 三张截图（全部 → 刚切空类目 → 稍后）供对比钉位是否残留。
final class MapFilterReproTests: XCTestCase {
    @MainActor
    func testSwitchToEmptyCategory() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]

        addUIInterruptionMonitor(withDescription: "系统弹窗") { alert in
            for label in ["允许", "Allow", "好", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        app.launch()

        let tab = app.buttons["足迹"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "底栏足迹未出现")
        tab.tap()
        sleep(1)
        attach(app, name: "0-列表")

        // 坐标级横划（元素级 swipeLeft 距离太短，会被当成点击触发跳转）
        let cityText = app.staticTexts["上海"]
        XCTAssertTrue(cityText.waitForExistence(timeout: 5), "进行中卡未出现")
        let rowY = cityText.frame.midY / app.frame.height
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: rowY))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: rowY)))
        sleep(1)
        attach(app, name: "0b-左滑删除")

        // 点卡片空白处应收起而非跳转
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: rowY)).tap()
        sleep(1)
        attach(app, name: "0c-点卡收起")

        // 再滑开点「删除」：确认弹窗必须出现（收起层挡按钮的回归验证）
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: rowY))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: rowY)))
        sleep(1)
        app.buttons["删除"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3), "删除确认弹窗未出现")
        attach(app, name: "0d-删除确认")
        app.alerts.firstMatch.buttons["取消"].tap()
        sleep(1)

        let mapChip = app.buttons["地图"]
        XCTAssertTrue(mapChip.waitForExistence(timeout: 5), "地图分段未出现")
        mapChip.tap()
        sleep(4)   // 等地图与钉渲染
        attach(app, name: "1-全部")

        let emptyCat = app.buttons["出行"]
        XCTAssertTrue(emptyCat.waitForExistence(timeout: 5), "筛选 chips 未出现")
        emptyCat.tap()
        sleep(2)
        attach(app, name: "2-切空类目")

        XCTAssertTrue(app.staticTexts["还没有带地点的记忆"].waitForExistence(timeout: 3),
                      "空态文案未出现")
        sleep(2)
        attach(app, name: "3-空类目稍后")

        app.buttons["全部"].tap()
        sleep(2)
        attach(app, name: "4-切回全部")
    }

    /// 时间线：封盘卡左滑（有记忆先拦截）、记忆左滑确认、管理模式多选
    @MainActor
    func testTimelineSwipeAndManage() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()

        let tab = app.buttons["足迹"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "底栏足迹未出现")
        tab.tap()
        let card = app.staticTexts["上海"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "进行中卡未出现")
        card.tap()   // 进见面详情（时间线）

        // 封盘卡左滑：第 1 天还有 1 条记忆 → 应弹「还不能删除」
        let seal = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "封盘 · 晚安")).firstMatch
        XCTAssertTrue(seal.waitForExistence(timeout: 5), "封盘卡未出现")
        let sealY = seal.frame.midY / app.frame.height
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: sealY))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: sealY)))
        sleep(1)
        XCTAssertTrue(app.buttons["删除"].waitForExistence(timeout: 2), "封盘卡左滑未展开")
        app.buttons["删除"].tap()
        XCTAssertTrue(app.alerts["还不能删除"].waitForExistence(timeout: 3), "拦截弹窗未出现")
        attach(app, name: "T1-封盘拦截")
        app.alerts.firstMatch.buttons["好"].tap()
        sleep(1)

        // 记忆卡左滑 → 删除确认
        let moment = app.staticTexts["演示昨日"]
        XCTAssertTrue(moment.waitForExistence(timeout: 5), "昨日记忆未出现")
        let momentY = moment.frame.midY / app.frame.height
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: momentY))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: momentY)))
        sleep(1)
        XCTAssertTrue(app.buttons["删除"].waitForExistence(timeout: 2), "记忆卡左滑未展开")
        app.buttons["删除"].tap()
        XCTAssertTrue(app.alerts["删除这条记忆？"].waitForExistence(timeout: 3), "记忆删除确认未出现")
        attach(app, name: "T2-记忆删除确认")
        app.alerts.firstMatch.buttons["取消"].tap()
        sleep(1)

        // 管理模式：勾一条 → 底栏出现删除所选
        app.buttons["管理"].tap()
        sleep(1)
        app.staticTexts["演示午餐"].tap()
        sleep(1)
        attach(app, name: "T3-管理模式")
        XCTAssertTrue(app.staticTexts["已选 1 项"].exists, "底栏计数未出现")
        app.buttons["完成"].tap()
        sleep(1)

        // 进行中编辑表单：实际开始 + 预计结束（反馈：行程延后要能改结束）
        app.buttons["编辑"].tap()
        XCTAssertTrue(app.staticTexts["预计结束"].waitForExistence(timeout: 3), "预计结束行未出现")
        attach(app, name: "T4-进行中编辑")
        app.buttons["取消"].tap()
    }

    /// 小本本详情页观感截图
    @MainActor
    func testLedgerDetailLook() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()

        let tab = app.buttons["小本本"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "底栏小本本未出现")
        tab.tap()
        let row = app.staticTexts["陪我逛了一下午书店"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "种子条目未出现")
        row.tap()
        sleep(2)
        attach(app, name: "L1-小本本详情")
    }

    /// 她页三屏观感截图：主页四点月历 / 记录卡 / 统计页
    @MainActor
    func testHerPageLook() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()

        let tab = app.buttons["她"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "底栏她未出现")
        tab.tap()
        sleep(2)
        attach(app, name: "H1-她页主页")

        // 点今天 → 记录卡（种子里今天在经期中：应见三排点选）
        let todayNum = Calendar.current.component(.day, from: Date())
        app.staticTexts["\(todayNum)"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["疼痛"].waitForExistence(timeout: 3), "点选排未出现")
        attach(app, name: "H2-记录卡")

        app.buttons["亲密活动"].tap()
        XCTAssertTrue(app.staticTexts["有措施"].waitForExistence(timeout: 3), "亲密段未出现")
        attach(app, name: "H2b-记录卡亲密段")

        app.buttons["完成"].tap()
        sleep(1)

        app.buttons["统计"].tap()
        XCTAssertTrue(app.staticTexts["历史周期"].waitForExistence(timeout: 3), "统计页未出现")
        attach(app, name: "H3-统计页")
    }

    /// 反馈⑥：今天卡 / 记得做段 / 她月历紫窗
    @MainActor
    func testRound6Look() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()

        XCTAssertTrue(app.staticTexts["📌 帮她带充电宝"].waitForExistence(timeout: 10), "今天卡未出现")
        attach(app, name: "R1-今天卡")

        app.buttons["小本本"].tap()
        // 反馈⑨T6:小本本新壳段名「记得做」→「待办」，且不再分「📌 我做/Ta做」两组（平列表+筛选行）
        app.buttons["待办"].tap()
        XCTAssertTrue(app.staticTexts["帮她带充电宝"].waitForExistence(timeout: 3), "待办段条目未出现")
        attach(app, name: "R2-待办段")

        // R4：记得做表单开关态。⊕ 弹层里的「记得做」格是图标+文字合成的无障碍标签，坐标/标签定位都不稳，
        // 降级走更稳的路径：点自己写的条目（"查演出票"，种子里 authorID=我，可编辑）直接进编辑表单截同款。
        let myTodo = app.staticTexts["查演出票"]
        XCTAssertTrue(myTodo.waitForExistence(timeout: 3), "自建待办条目未出现")
        myTodo.tap()
        XCTAssertTrue(app.navigationBars["编辑待办"].waitForExistence(timeout: 3), "待办编辑表单未弹出")
        XCTAssertTrue(app.switches["私密"].waitForExistence(timeout: 2) || app.staticTexts["私密"].exists,
                      "私密开关未出现")
        attach(app, name: "R4-表单开关态")
        app.buttons["取消"].tap()
        sleep(1)

        app.buttons["她"].tap()
        sleep(2)
        attach(app, name: "R3-她月历紫窗")
    }

    /// 反馈⑧bug1 回归：单地点打开地图，钉必须渲染（点中心命中钉 → 抽屉出现）
    @MainActor
    func testSinglePinRenders() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo", "--seed-single-place"]
        app.launch()
        app.buttons["足迹"].tap()
        let mapChip = app.buttons["地图"]
        XCTAssertTrue(mapChip.waitForExistence(timeout: 8))
        mapChip.tap()
        sleep(4)
        attach(app, name: "S1-单钉")
        // 演示餐厅无照片 → 钉显示 fallback 首字「演」，直接按元素点（不依赖屏幕坐标）
        let pin = app.staticTexts["演"]
        XCTAssertTrue(pin.waitForExistence(timeout: 6), "单钉未渲染（反馈⑧bug1 回归）")
        pin.tap()
        XCTAssertTrue(app.staticTexts["演示餐厅"].waitForExistence(timeout: 3),
                      "点钉未打开地点抽屉")
        attach(app, name: "S2-单钉抽屉")
    }

    /// 反馈⑧:计划→回忆转化流水线(已备卡/待办卡/点圈开表单转化/结束后灰卡)
    /// 反馈⑨T4改造:备忘(day==nil)已从主时间线剥离，只在左缘侧签弹窗展示，永不转化(§一)；
    /// 待办圈不再秒转化，点圈打开「补全这段回忆」预填表单，保存才转化(§二 2A)。
    @MainActor
    func testRound8PlanFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()
        app.buttons["足迹"].tap()
        let card = app.staticTexts["上海"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), "进行中卡未出现")
        card.tap()
        // 进行中:行前已备 + 待办卡；备忘(给她妈带特产/买伴手礼)已被 T4 剥离出主时间线卡流，
        // 不再有「接下来 · 还没做」组里的备忘卡
        XCTAssertTrue(app.staticTexts["行前已备 · 1"].waitForExistence(timeout: 5), "已备组未出现")
        XCTAssertTrue(app.staticTexts["买火车票"].exists, "已备划线卡未出现")
        // 「计划」chip 应已消失(进行中)
        XCTAssertFalse(app.buttons["计划"].exists, "进行中不应再有计划 chip")
        // 反馈⑨T4:备忘剥离进左缘侧签——竖排书签是「备」「忘」「N」三个独立 Text 拼成一个按钮，
        // 系统无障碍把子 Text 的 label 用「, 」拼接成整按钮的组合 label（实测导出视图树确认，
        // 不是简单的「备忘 N」一句话）；种子 2 条备忘 = 给她妈带特产+买伴手礼
        // （「买火车票」day != nil 走「行前已备」，不算备忘——见 DebugSeeder.swift 的 T7 注释）
        let memoTab = app.buttons["备忘 2"]
        XCTAssertTrue(memoTab.waitForExistence(timeout: 5), "备忘侧签未出现")
        attach(app, name: "R8-1-进行中时间线")
        // tap 侧签 → 半屏弹窗，备忘条目在里面，纯划线不转化
        memoTab.tap()
        XCTAssertTrue(app.navigationBars["备忘"].waitForExistence(timeout: 3), "备忘弹窗未弹出")
        XCTAssertTrue(app.staticTexts["给她妈带特产"].exists, "备忘弹窗条目未出现")
        attach(app, name: "R8-1b-备忘侧签弹窗")
        app.buttons["关闭"].tap()
        sleep(1)
        // 点圈(反馈⑨T2A：不再秒转化)→ 打开「补全这段回忆」表单，预填标题，点「保存」才转化
        let toggle = app.buttons["划掉 去码头拍日落"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "待办圈未出现")
        toggle.tap()
        XCTAssertTrue(app.navigationBars["补全这段回忆"].waitForExistence(timeout: 3), "补全这段回忆表单未弹出")
        let titleField = app.textFields["如 蟹家大院"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2), "标题栏未出现")
        XCTAssertEqual(titleField.value as? String, "去码头拍日落", "标题栏未预填")
        app.buttons["保存"].tap()
        sleep(1)
        XCTAssertFalse(app.buttons["划掉 去码头拍日落"].exists, "转化后圈应消失")
        XCTAssertTrue(app.staticTexts["去码头拍日落"].exists, "转化后的记忆卡不见了")
        attach(app, name: "R8-2-转化后")
        // 结束见面 → 灰卡(江边看夜景是种子里唯一未转化的真日程，才会落"没做成的计划"；
        // 备忘 day==nil 已被 T4 剥离，不再能充当灰卡)
        app.buttons["结束见面"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        app.alerts.firstMatch.buttons["结束见面"].tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["没做成的计划"].waitForExistence(timeout: 5), "灰卡组未出现")
        XCTAssertTrue(app.staticTexts["江边看夜景"].exists, "灰卡未出现")
        // 备忘(给她妈带特产/买伴手礼)结束后仍存档在侧签，不随结束见面消失
        XCTAssertTrue(app.buttons["备忘 2"].exists, "结束后备忘侧签应仍在")
        attach(app, name: "R8-3-结束后灰卡")
    }

    /// 反馈⑨:时间线左缘侧签+弹窗观感 / 小本本新壳四段+二级筛选观感截图
    @MainActor
    func testRound9Look() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()
        app.buttons["足迹"].tap()
        let card = app.staticTexts["上海"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), "进行中卡未出现")
        card.tap()

        // S1:时间线左缘侧签(墨底白字竖排「备/忘/N」)
        let memoTab = app.buttons["备忘 2"]
        XCTAssertTrue(memoTab.waitForExistence(timeout: 5), "备忘侧签未出现")
        attach(app, name: "R9-S1-时间线侧签")

        // S2:侧签弹窗
        memoTab.tap()
        XCTAssertTrue(app.navigationBars["备忘"].waitForExistence(timeout: 3), "备忘弹窗未弹出")
        attach(app, name: "R9-S2-侧签弹窗")

        // 反馈⑫回归锁(T6 评审 carry-to-T7):圆圈双点。修复前 List 对同 id 行有值缓存,
        // FetchRequest 整体失效才重绘,第 2+n 次勾选数据已变但界面不动;行级 @ObservedObject
        // 订阅(TimelineListView.MemoRow)后每次 toggle 都驱动本行重绘,无障碍标签随 isDone
        // 动态显「划掉/恢复 标题」。种子「给她妈带特产」isDone 初始 false → 初始态「划掉」。
        let memoToggle = app.buttons["划掉 给她妈带特产"]
        XCTAssertTrue(memoToggle.waitForExistence(timeout: 3), "备忘勾选圆圈未出现")
        memoToggle.tap()
        XCTAssertTrue(app.buttons["恢复 给她妈带特产"].waitForExistence(timeout: 2),
                      "第 1 次点击未翻转为「恢复」")
        app.buttons["恢复 给她妈带特产"].tap()
        XCTAssertTrue(app.buttons["划掉 给她妈带特产"].waitForExistence(timeout: 2),
                      "第 2 次点击未翻回「划掉」(反馈⑫行级订阅重绘回归)")

        // P6-T6 回归锁(评审 carry-to-T7):点行正文同样触发勾选,不止圆圈本身——「整行可勾」。
        // 上面两次点击已把状态还原到「划掉」,点行是第 3 次翻转,应变「恢复」。
        app.staticTexts["给她妈带特产"].tap()
        XCTAssertTrue(app.buttons["恢复 给她妈带特产"].waitForExistence(timeout: 2),
                      "点行正文未触发勾选(整行可勾回归)")

        app.buttons["关闭"].tap()
        sleep(1)

        // 小本本新壳:四段 tab + 二级筛选（反馈⑨T6）
        app.buttons["小本本"].tap()
        XCTAssertTrue(app.staticTexts["陪我逛了一下午书店"].waitForExistence(timeout: 5), "好事段未出现")
        XCTAssertTrue(app.buttons["好事"].exists, "「好事」tab 未出现")
        XCTAssertTrue(app.buttons["生气"].exists, "「生气」tab 未出现")
        XCTAssertTrue(app.buttons["喜好"].exists, "「喜好」tab 未出现")
        XCTAssertTrue(app.buttons["待办"].exists, "「待办」tab 未出现")
        XCTAssertTrue(app.buttons["私密箱"].exists, "好事段二级筛选「私密箱」未出现")
        // S3:好事段(默认落段)
        attach(app, name: "R9-S3-小本本好事段")

        // S4:待办段——平列表(不再分「我做/Ta做」两组)，二级筛选同样生效
        app.buttons["待办"].tap()
        XCTAssertTrue(app.staticTexts["帮她带充电宝"].waitForExistence(timeout: 3), "待办段条目未出现")
        XCTAssertTrue(app.buttons["全部"].exists, "待办段二级筛选「全部」未出现")
        attach(app, name: "R9-S4-小本本待办段")
    }

    /// 反馈⑦：计划/记得做钉与按次筛选
    @MainActor
    func testRound7MapLook() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()
        app.buttons["足迹"].tap()
        let mapChip = app.buttons["地图"]
        XCTAssertTrue(mapChip.waitForExistence(timeout: 8))
        mapChip.tap()
        sleep(3)
        XCTAssertTrue(app.buttons["计划"].exists, "计划筛选未出现")
        // 筛选行变长，计划/记得做在屏幕右侧外：先把 chips 行横滑到底
        let chipsY = app.buttons["美食"].frame.midY / app.frame.height
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: chipsY))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: chipsY)))
        sleep(1)
        app.buttons["计划"].tap()
        sleep(2)
        XCTAssertFalse(app.staticTexts["还没有带地点的记忆"].exists, "计划筛选下应有码头钉")
        attach(app, name: "P1-计划筛选")
        app.buttons["待办"].tap()
        sleep(2)
        XCTAssertFalse(app.staticTexts["还没有带地点的记忆"].exists, "待办筛选下应有花店钉")
        attach(app, name: "P2-待办筛选")
        // 滑回行首再开见面菜单
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: chipsY))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: chipsY)))
        sleep(1)
        app.buttons["全部见面 ▾"].tap()
        sleep(1)
        app.buttons["第 1 次见面"].tap()
        sleep(2)
        attach(app, name: "P3-按次筛选")
    }

    /// 临时复现：记忆详情→档案→在地图中查看 的小地图点位
    @MainActor
    func testMiniMapPinRepro() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()
        app.buttons["足迹"].tap()
        let card = app.staticTexts["上海"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        let moment = app.staticTexts["演示午餐"]
        XCTAssertTrue(moment.waitForExistence(timeout: 5))
        moment.tap()
        let placeRow = app.buttons["演示餐厅"]
        XCTAssertTrue(placeRow.waitForExistence(timeout: 5), "记忆详情地点行未出现")
        placeRow.tap()
        let mapBtn = app.buttons["在地图中查看 ›"]
        XCTAssertTrue(mapBtn.waitForExistence(timeout: 5), "档案页未出现")
        mapBtn.tap()
        sleep(4)
        attach(app, name: "M1-小地图")
    }

    /// R17 §五:完成开关点按后行必须立刻重绘(R12 MemoRow 同族回归)。
    /// 断言锚点=勾选圈显式 label 翻转(完成 x ↔ 取消完成 x),双击验证第二次点按仍重绘。
    @MainActor
    func testTodoToggleRedrawsRow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-map-demo"]
        app.launch()

        app.buttons["小本本"].tap()
        let todosTab = app.buttons["待办"]
        XCTAssertTrue(todosTab.waitForExistence(timeout: 8), "小本本四段未出现")
        todosTab.tap()

        let toggle = app.buttons["完成 查演出票"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "勾选圈未带显式 label")
        toggle.tap()
        XCTAssertTrue(app.buttons["取消完成 查演出票"].waitForExistence(timeout: 3),
                      "第一次点按后行未重绘")
        app.buttons["取消完成 查演出票"].tap()
        XCTAssertTrue(app.buttons["完成 查演出票"].waitForExistence(timeout: 3),
                      "第二次点按后行未重绘(R12 同族值缓存)")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
