import XCTest
@testable import Anniversary

final class CyclePredictorTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func d(_ day: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(day) * 86_400) }

    /// 完整周期开始日间隔 30/26、行经 5/7/6 → 均值 28/6
    private let threeCompleted: [(start: Date, end: Date?)] = [
        (Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 4 * 86_400)),
        (Date(timeIntervalSince1970: 30 * 86_400), Date(timeIntervalSince1970: 36 * 86_400)),
        (Date(timeIntervalSince1970: 56 * 86_400), Date(timeIntervalSince1970: 61 * 86_400)),
    ]

    func testDefaultsWhenFewerThanTwoCompleted() {
        let p = CyclePredictor.predict(cycles: [(start: d(0), end: nil)], today: d(2), calendar: cal)
        XCTAssertTrue(p.isDefault)
        XCTAssertNil(p.learnedCycleLength)
        XCTAssertEqual(p.cycleLength, 28)
        XCTAssertEqual(p.periodLength, 7)
        XCTAssertEqual(p.nextStarts, [d(28), d(56), d(84)])   // 基准=最近开始日 d0
        XCTAssertEqual(p.scheduledNextStart, d(28))
        XCTAssertEqual(p.ongoingEnd, d(6))                    // 0 + 7 - 1
        XCTAssertNil(p.overdueDays)
    }

    func testMeansUseLastSixIntervalsAndDurations() {
        let p = CyclePredictor.predict(cycles: threeCompleted, today: d(70), calendar: cal)
        XCTAssertFalse(p.isDefault)
        XCTAssertEqual(p.learnedCycleLength, 28)
        XCTAssertEqual(p.learnedPeriodLength, 6)
        XCTAssertEqual(p.cycleLength, 28)
        XCTAssertEqual(p.periodLength, 6)                     // (5+7+6)/3
        XCTAssertEqual(p.nextStarts.first, d(84))             // 56 + 28
        XCTAssertNil(p.ongoingEnd)                            // 无进行中
        XCTAssertNil(p.overdueDays)
    }

    // MARK: - R20 顺延

    func testOverdueShiftsWholeForecastToToday() {
        // 表定 d84(56+28),今天 d87 还没来:三个预测窗整体锚到今天,后续按周期递推
        let p = CyclePredictor.predict(cycles: threeCompleted, today: d(87), calendar: cal)
        XCTAssertEqual(p.overdueDays, 3)
        XCTAssertEqual(p.scheduledNextStart, d(84))           // 口径:落库「当时预测」仍用表定
        XCTAssertEqual(p.nextStarts, [d(87), d(115), d(143)])
    }

    func testScheduledDayItselfIsNotOverdue() {
        let p = CyclePredictor.predict(cycles: threeCompleted, today: d(84), calendar: cal)
        XCTAssertNil(p.overdueDays)                           // 当天不算推迟
        XCTAssertEqual(p.nextStarts.first, d(84))
    }

    func testOngoingSuppressesOverdueAndShift() {
        // 有进行中段就谈不上「推迟」:预测锚保持表定不顺延
        let p = CyclePredictor.predict(cycles: [(d(0), nil)], today: d(40), calendar: cal)
        XCTAssertNil(p.overdueDays)
        XCTAssertEqual(p.nextStarts.first, d(28))
    }

    func testOngoingEndNeverInThePast() {
        // 经期进行中超过预计长度:预计结束顺到今天,不再显示过去日期
        let p = CyclePredictor.predict(cycles: [(d(0), nil)], today: d(9), calendar: cal)
        XCTAssertEqual(p.ongoingEnd, d(9))                    // 表定 d6 已过
    }

    // MARK: - R20-② 设置取值:手动 > 记录均值 > 28/7

    func testManualPrefsWinWhenDataInsufficient() {
        // 完整周期 <2:手动值直接生效(排卵窗挂 nextStarts−14,自动跟着科学推算)
        let p = CyclePredictor.predict(cycles: [(d(0), d(4))], prefs: (35, 5),
                                       today: d(10), calendar: cal)
        XCTAssertFalse(p.isDefault)                           // 两分量均手动,无兜底
        XCTAssertEqual(p.cycleLength, 35)
        XCTAssertEqual(p.periodLength, 5)
        XCTAssertEqual(p.nextStarts.first, d(35))
    }

    func testManualPrefsOverrideLearnedRecords() {
        // R20-② 反馈修:手动设置始终生效,不被记录均值压住(31/7 卡死案)
        let p = CyclePredictor.predict(cycles: threeCompleted, prefs: (35, 5),
                                       today: d(70), calendar: cal)
        XCTAssertEqual(p.cycleLength, 35)
        XCTAssertEqual(p.periodLength, 5)
        XCTAssertEqual(p.learnedCycleLength, 28)              // 学习值仍算出(设置页展示)
        XCTAssertEqual(p.nextStarts.first, d(91))             // 56 + 35
    }

    func testMixedManualCycleAutoPeriod() {
        // 分量独立:周期手动 35,经期自动挡吃记录均值 6
        let p = CyclePredictor.predict(cycles: threeCompleted, prefs: (35, nil),
                                       today: d(70), calendar: cal)
        XCTAssertEqual(p.cycleLength, 35)
        XCTAssertEqual(p.periodLength, 6)
        XCTAssertFalse(p.isDefault)
    }

    func testAutoComponentFallsBackWhenDataInsufficient() {
        // 经期手动 5、周期自动挡且数据不足:周期回落 28,仍标「数据积累中」
        let p = CyclePredictor.predict(cycles: [(d(0), d(4))], prefs: (nil, 5),
                                       today: d(10), calendar: cal)
        XCTAssertEqual(p.cycleLength, 28)
        XCTAssertEqual(p.periodLength, 5)
        XCTAssertTrue(p.isDefault)
    }

    // MARK: - 既有口径

    func testDeviationDays() {
        XCTAssertEqual(CyclePredictor.deviationDays(predictedAtLogging: d(10), actualStart: d(12), calendar: cal), 2)
        XCTAssertEqual(CyclePredictor.deviationDays(predictedAtLogging: d(10), actualStart: d(8), calendar: cal), -2)
        XCTAssertNil(CyclePredictor.deviationDays(predictedAtLogging: nil, actualStart: d(8), calendar: cal))
    }

    func testOvulationWindowsFromHistoryAndPredictions() {
        // 历史两段（开始 d0、d28）→ 历史窗 1 个（依据 d28）：排卵日 d14，days d9…d18
        // nextStarts [d56] → 未来窗 1 个：排卵日 d42，days d37…d46
        let windows = CyclePredictor.ovulationWindows(
            cycles: [(d(0), d(5)), (d(28), d(33))],
            nextStarts: [d(56)], calendar: cal)
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].ovulationDay, d(14))
        XCTAssertEqual(windows[0].days.first, d(9))
        XCTAssertEqual(windows[0].days.count, 10)
        XCTAssertEqual(windows[0].days.last, d(18))
        XCTAssertEqual(windows[1].ovulationDay, d(42))
    }

    func testOvulationWindowsSingleCycleUsesPredictionsOnly() {
        let windows = CyclePredictor.ovulationWindows(
            cycles: [(d(0), nil)], nextStarts: [d(28), d(56), d(84)], calendar: cal)
        XCTAssertEqual(windows.count, 3)                           // 无相邻历史对，只有预测窗
        XCTAssertEqual(windows[0].ovulationDay, d(14))
    }
}
