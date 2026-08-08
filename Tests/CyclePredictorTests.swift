import XCTest
@testable import Anniversary

final class CyclePredictorTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func d(_ day: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(day) * 86_400) }

    func testDefaultsWhenFewerThanTwoCompleted() {
        let p = CyclePredictor.predict(cycles: [(start: d(0), end: nil)], calendar: cal)
        XCTAssertTrue(p.isDefault)
        XCTAssertEqual(p.cycleLength, 28)
        XCTAssertEqual(p.periodLength, 7)
        XCTAssertEqual(p.nextStarts, [d(28), d(56), d(84)])   // 基准=最近开始日 d0
        XCTAssertEqual(p.ongoingEnd, d(6))                    // 0 + 7 - 1
    }

    func testMeansUseLastSixIntervalsAndDurations() {
        // 完整周期开始日间隔 30/26，行经 5/7 → 周期 28、行经 6
        let cycles: [(Date, Date?)] = [
            (d(0), d(4)), (d(30), d(36)), (d(56), d(61)),
        ]
        let p = CyclePredictor.predict(cycles: cycles, calendar: cal)
        XCTAssertFalse(p.isDefault)
        XCTAssertEqual(p.cycleLength, 28)
        XCTAssertEqual(p.periodLength, 6)                     // (5+7+6)/3
        XCTAssertEqual(p.nextStarts.first, d(84))             // 56 + 28
        XCTAssertNil(p.ongoingEnd)                            // 无进行中
    }

    func testDelayDaysOnlyWithoutOngoing() {
        XCTAssertEqual(CyclePredictor.delayDays(nextStart: d(10), hasOngoing: false,
                                                today: d(12), calendar: cal), 2)
        XCTAssertNil(CyclePredictor.delayDays(nextStart: d(10), hasOngoing: false,
                                              today: d(10), calendar: cal))   // 当天不算推迟
        XCTAssertNil(CyclePredictor.delayDays(nextStart: d(10), hasOngoing: true,
                                              today: d(12), calendar: cal))
    }

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
