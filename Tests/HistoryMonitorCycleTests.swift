import XCTest
@testable import Anniversary

final class HistoryMonitorCycleTests: XCTestCase {
    func testCycleNotifiableOnlyWhenOngoingInsert() {
        XCTAssertTrue(HistoryMonitor.cycleNotifiable(endDate: nil))        // 经期开始
        XCTAssertFalse(HistoryMonitor.cycleNotifiable(endDate: Date()))    // 补录起止俱全：不惊动
    }
}
