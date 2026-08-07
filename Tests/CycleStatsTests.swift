import XCTest
@testable import Anniversary

final class CycleStatsTests: XCTestCase {
    func testPainRate() {
        XCTAssertNil(CycleStats.painRate(painRaws: []))
        XCTAssertEqual(CycleStats.painRate(painRaws: [1, 2, 3, 1])!, 0.5, accuracy: 0.001)
    }
    func testOnTimeRate() {
        XCTAssertNil(CycleStats.onTimeRate(deviations: []))
        XCTAssertNil(CycleStats.onTimeRate(deviations: [nil]))        // 全补录无样本
        XCTAssertEqual(CycleStats.onTimeRate(deviations: [0, 2, -3, nil])!, 2.0 / 3.0, accuracy: 0.001)
    }
}
