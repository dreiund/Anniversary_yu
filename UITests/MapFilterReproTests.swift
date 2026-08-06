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

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
