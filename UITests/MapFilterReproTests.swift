import XCTest

/// 地图筛选切空类目的复现脚本：种子数据只有 美食/景点公园 两类，切「咖啡甜品」应清空钉位。
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

        let emptyCat = app.buttons["咖啡甜品"]
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
        app.buttons["记得做"].tap()
        XCTAssertTrue(app.staticTexts["📌 我做"].waitForExistence(timeout: 3), "记得做段未出现")
        attach(app, name: "R2-记得做段")

        // R4：记得做表单开关态。⊕ 弹层里的「记得做」格是图标+文字合成的无障碍标签，坐标/标签定位都不稳，
        // 降级走更稳的路径：点自己写的条目（"查演出票"，种子里 authorID=我，可编辑）直接进编辑表单截同款。
        let myTodo = app.staticTexts["查演出票"]
        XCTAssertTrue(myTodo.waitForExistence(timeout: 3), "自建记得做条目未出现")
        myTodo.tap()
        XCTAssertTrue(app.navigationBars["编辑记得做"].waitForExistence(timeout: 3), "记得做编辑表单未弹出")
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
        app.buttons["记得做"].tap()
        sleep(2)
        XCTAssertFalse(app.staticTexts["还没有带地点的记忆"].exists, "记得做筛选下应有花店钉")
        attach(app, name: "P2-记得做筛选")
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

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
