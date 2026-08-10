import XCTest
@testable import Anniversary

final class ReminderPlannerTests: XCTestCase {
    func testIDs() {
        let u = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        XCTAssertEqual(ReminderPlanner.todoID(u), "todo-11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(ReminderPlanner.planID(u), "plan-11111111-2222-3333-4444-555555555555")
    }
    func testShouldSchedule() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(ReminderPlanner.shouldSchedule(remindAt: nil, isDone: false, now: now))
        XCTAssertFalse(ReminderPlanner.shouldSchedule(remindAt: Date(timeIntervalSince1970: 999), isDone: false, now: now))
        XCTAssertTrue(ReminderPlanner.shouldSchedule(remindAt: Date(timeIntervalSince1970: 1_001), isDone: false, now: now))
    }

    /// P6-B3 回归：勾掉的事项就算 remindAt 仍是未来时间也不该再排程——
    /// 堵「勾掉后编辑保存复活提醒」（表单编辑保存时 isDone 已为真，但 remindAt 字段本身没被清）。
    func testShouldScheduleFalseWhenDone() {
        let now = Date(timeIntervalSince1970: 1_000)
        let futureRemindAt = Date(timeIntervalSince1970: 1_001)
        XCTAssertFalse(ReminderPlanner.shouldSchedule(remindAt: futureRemindAt, isDone: true, now: now))
    }
}
