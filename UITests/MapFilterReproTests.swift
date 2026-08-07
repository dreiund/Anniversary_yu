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
        app.buttons["完成"].tap()
        sleep(1)

        app.buttons["统计"].tap()
        XCTAssertTrue(app.staticTexts["历史周期"].waitForExistence(timeout: 3), "统计页未出现")
        attach(app, name: "H3-统计页")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
