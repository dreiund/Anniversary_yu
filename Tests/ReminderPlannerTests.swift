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
        XCTAssertFalse(ReminderPlanner.shouldSchedule(remindAt: nil, now: now))
        XCTAssertFalse(ReminderPlanner.shouldSchedule(remindAt: Date(timeIntervalSince1970: 999), now: now))
        XCTAssertTrue(ReminderPlanner.shouldSchedule(remindAt: Date(timeIntervalSince1970: 1_001), now: now))
    }
}
