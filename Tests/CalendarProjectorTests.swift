import XCTest
@testable import Anniversary

final class CalendarProjectorTests: XCTestCase {
    private let cal = Calendar.current

    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: day, hour: h))!
    }
    private func day0(_ y: Int, _ m: Int, _ day: Int) -> Date {
        cal.startOfDay(for: d(y, m, day))
    }
    private func cell(_ cells: [CalCell], _ y: Int, _ m: Int, _ day: Int) -> CalCell {
        cells.first { cal.isDate($0.day, inSameDayAs: day0(y, m, day)) }!
    }

    // 8/17 0:30 的记录：自然日归 17，约会日归 16（spec §3.2）
    func testCrossMidnightMomentMovesInDateDayMode() {
        let m = [CalMomentInput(happenedDay: day0(2026, 8, 17), dateDayDay: day0(2026, 8, 16))]
        let meetings = [CalMeetingInput(index: 3, firstDay: day0(2026, 8, 14), lastDay: day0(2026, 8, 16))]
        let natural = CalendarProjector.cells(monthAnchor: day0(2026, 8, 1), today: day0(2026, 8, 5),
                                              mode: .natural, moments: m, moods: [], meetings: meetings, calendar: cal)
        XCTAssertTrue(cell(natural, 2026, 8, 17).hasMoment)
        XCTAssertFalse(cell(natural, 2026, 8, 16).hasMoment)
        let dd = CalendarProjector.cells(monthAnchor: day0(2026, 8, 1), today: day0(2026, 8, 5),
                                         mode: .dateDay, moments: m, moods: [], meetings: meetings, calendar: cal)
        XCTAssertFalse(cell(dd, 2026, 8, 17).hasMoment)
        XCTAssertTrue(cell(dd, 2026, 8, 16).hasMoment)
    }

    // 见面带位置与「第 n 次」标注（当月首格）、D 标仅约会日模式
    func testBandPositionsLabelAndDTags() {
        let meetings = [CalMeetingInput(index: 3, firstDay: day0(2026, 8, 14), lastDay: day0(2026, 8, 16))]
        let natural = CalendarProjector.cells(monthAnchor: day0(2026, 8, 1), today: day0(2026, 8, 5),
                                              mode: .natural, moments: [], moods: [], meetings: meetings, calendar: cal)
        XCTAssertEqual(cell(natural, 2026, 8, 14).band, .start)
        XCTAssertEqual(cell(natural, 2026, 8, 15).band, .middle)
        XCTAssertEqual(cell(natural, 2026, 8, 16).band, .end)
        XCTAssertEqual(cell(natural, 2026, 8, 14).bandLabel, "第 3 次")
        XCTAssertNil(cell(natural, 2026, 8, 15).bandLabel)
        XCTAssertNil(cell(natural, 2026, 8, 14).dTag)          // 自然日无 D 标
        let dd = CalendarProjector.cells(monthAnchor: day0(2026, 8, 1), today: day0(2026, 8, 5),
                                         mode: .dateDay, moments: [], moods: [], meetings: meetings, calendar: cal)
        XCTAssertEqual(cell(dd, 2026, 8, 14).dTag, "D1")
        XCTAssertEqual(cell(dd, 2026, 8, 16).dTag, "D3")
    }

    // 跨月见面（7/30–8/2）：8 月视图带从月首延续，「第 n 次」标在 8/1（当月首格）
    func testCrossMonthBandLabelsFirstInMonthCell() {
        let meetings = [CalMeetingInput(index: 2, firstDay: day0(2026, 7, 30), lastDay: day0(2026, 8, 2))]
        let cells = CalendarProjector.cells(monthAnchor: day0(2026, 8, 1), today: day0(2026, 8, 5),
                                            mode: .natural, moments: [], moods: [], meetings: meetings, calendar: cal)
        XCTAssertEqual(cell(cells, 2026, 8, 1).band, .middle)
        XCTAssertEqual(cell(cells, 2026, 8, 1).bandLabel, "第 2 次")
        XCTAssertEqual(cell(cells, 2026, 8, 2).band, .end)
    }

    // 聚焦压灰：约会日模式非见面日 faded；今天照常 isToday
    func testFocusFadingOnlyInDateDayMode() {
        let meetings = [CalMeetingInput(index: 3, firstDay: day0(2026, 8, 14), lastDay: day0(2026, 8, 16))]
        let dd = CalendarProjector.cells(monthAnchor: day0(2026, 8, 1), today: day0(2026, 8, 5),
                                         mode: .dateDay, moments: [], moods: [], meetings: meetings, calendar: cal)
        XCTAssertTrue(cell(dd, 2026, 8, 5).faded)
        XCTAssertTrue(cell(dd, 2026, 8, 5).isToday)
        XCTAssertFalse(cell(dd, 2026, 8, 15).faded)
        let natural = CalendarProjector.cells(monthAnchor: day0(2026, 8, 1), today: day0(2026, 8, 5),
                                              mode: .natural, moments: [], moods: [], meetings: meetings, calendar: cal)
        XCTAssertFalse(cell(natural, 2026, 8, 5).faded)
    }

    // 心情恒按自然日；左我右 TA
    func testMoodsStayOnNaturalDayInBothModes() {
        let moods = [CalMoodInput(day: day0(2026, 8, 17), isMine: true, emoji: "😊"),
                     CalMoodInput(day: day0(2026, 8, 17), isMine: false, emoji: "🥰")]
        let meetings = [CalMeetingInput(index: 3, firstDay: day0(2026, 8, 14), lastDay: day0(2026, 8, 16))]
        for mode in [CalendarMode.natural, .dateDay] {
            let cells = CalendarProjector.cells(monthAnchor: day0(2026, 8, 1), today: day0(2026, 8, 5),
                                                mode: mode, moments: [], moods: moods, meetings: meetings, calendar: cal)
            XCTAssertEqual(cell(cells, 2026, 8, 17).myEmoji, "😊")
            XCTAssertEqual(cell(cells, 2026, 8, 17).partnerEmoji, "🥰")
        }
    }

    // 网格周一起始、首尾补齐整周
    func testGridStartsMondayAndPadsFullWeeks() {
        let cells = CalendarProjector.cells(monthAnchor: day0(2026, 8, 1), today: day0(2026, 8, 5),
                                            mode: .natural, moments: [], moods: [], meetings: [], calendar: cal)
        XCTAssertEqual(cells.count % 7, 0)
        XCTAssertEqual(cal.component(.weekday, from: cells.first!.day), 2)   // 周一（weekday 2）
        XCTAssertLessThanOrEqual(cells.first!.day, day0(2026, 8, 1))          // 首格不晚于 1 号
        XCTAssertTrue(cells.contains { cal.isDate($0.day, inSameDayAs: day0(2026, 8, 31)) && $0.inMonth })
    }

    // 小结：N=当月见面天数，M=当月按约会日归属的记忆数；N=0 有专属文案由 UI 处理
    func testSummaryCounts() {
        let meetings = [CalMeetingInput(index: 3, firstDay: day0(2026, 8, 14), lastDay: day0(2026, 8, 16))]
        let m = [CalMomentInput(happenedDay: day0(2026, 8, 17), dateDayDay: day0(2026, 8, 16)),
                 CalMomentInput(happenedDay: day0(2026, 8, 15), dateDayDay: day0(2026, 8, 15)),
                 CalMomentInput(happenedDay: day0(2026, 9, 1), dateDayDay: day0(2026, 9, 1))]
        let s = CalendarProjector.summary(monthAnchor: day0(2026, 8, 1), moments: m,
                                          meetings: meetings, calendar: cal)
        XCTAssertEqual(s.daysTogether, 3)
        XCTAssertEqual(s.momentCount, 2)   // 9/1 不算；8/17 凌晨条按归属 8/16 算进 8 月
    }

    // 跨月见面只数当月天数
    func testSummaryClampsCrossMonthMeeting() {
        let meetings = [CalMeetingInput(index: 2, firstDay: day0(2026, 7, 30), lastDay: day0(2026, 8, 2))]
        let s = CalendarProjector.summary(monthAnchor: day0(2026, 8, 1), moments: [],
                                          meetings: meetings, calendar: cal)
        XCTAssertEqual(s.daysTogether, 2)  // 8/1、8/2
    }
}
