import XCTest
@testable import Anniversary

final class PlaceMergeRuleTests: XCTestCase {
    // spec §七：名字相等或互为包含（trim 后），空名不参与
    func testNameSimilar() {
        XCTAssertTrue(PlaceMergeRule.nameSimilar("一尺花园", "一尺花园"))
        XCTAssertTrue(PlaceMergeRule.nameSimilar("一尺花园", "一尺花园(武康路店)"))
        XCTAssertTrue(PlaceMergeRule.nameSimilar("一尺花园(武康路店)", "一尺花园"))
        XCTAssertTrue(PlaceMergeRule.nameSimilar(" 一尺花园 ", "一尺花园"))
        XCTAssertFalse(PlaceMergeRule.nameSimilar("一尺花园", "两尺花园"))
        XCTAssertFalse(PlaceMergeRule.nameSimilar("", "一尺花园"))
        XCTAssertFalse(PlaceMergeRule.nameSimilar("  ", "一尺花园"))
    }

    // 50 米半径：同名 40m 命中、60m 不命中；异名 10m 也不命中
    func testIsCandidateByDistanceAndName() {
        // 纬度 31° 附近，纬向 1° ≈ 111km → 40m ≈ 0.00036°
        XCTAssertTrue(PlaceMergeRule.isCandidate(
            name: "一尺花园", latitude: 31.0, longitude: 121.0,
            existingName: "一尺花园", existingLatitude: 31.00036, existingLongitude: 121.0))
        XCTAssertFalse(PlaceMergeRule.isCandidate(
            name: "一尺花园", latitude: 31.0, longitude: 121.0,
            existingName: "一尺花园", existingLatitude: 31.00054, existingLongitude: 121.0))
        XCTAssertFalse(PlaceMergeRule.isCandidate(
            name: "一尺花园", latitude: 31.0, longitude: 121.0,
            existingName: "别家餐厅", existingLatitude: 31.00001, existingLongitude: 121.0))
    }
}
