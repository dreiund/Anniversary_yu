import XCTest
@testable import Anniversary

final class HistoryMonitorCycleTests: XCTestCase {
    func testCycleNotifiableOnlyWhenOngoingInsert() {
        let me = UUID(), her = UUID()
        XCTAssertTrue(HistoryMonitor.cycleNotifiable(endDate: nil, authorPartnerID: her, myID: me))       // 经期开始
        XCTAssertFalse(HistoryMonitor.cycleNotifiable(endDate: Date(), authorPartnerID: her, myID: me))   // 补录起止俱全：不惊动
    }

    // P6-T2：三分支——自己（含自己的第二台设备）记的不响；对方记的响；旧数据 author=nil 仍响（不静默）
    func testCycleNotifiableAuthorDimension() {
        let me = UUID(), her = UUID()
        XCTAssertFalse(HistoryMonitor.cycleNotifiable(endDate: nil, authorPartnerID: me, myID: me))    // 自己记不响
        XCTAssertTrue(HistoryMonitor.cycleNotifiable(endDate: nil, authorPartnerID: her, myID: me))    // 对方记响
        XCTAssertTrue(HistoryMonitor.cycleNotifiable(endDate: nil, authorPartnerID: nil, myID: me))    // 旧数据 nil 仍响
    }
}
