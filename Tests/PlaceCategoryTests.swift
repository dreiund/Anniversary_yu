import XCTest
@testable import Anniversary

final class PlaceCategoryTests: XCTestCase {
    // spec §二：raw 锁死，禁止改序/插入
    func testRawValuesLocked() {
        XCTAssertEqual(PlaceCategory.other.rawValue, 0)
        XCTAssertEqual(PlaceCategory.food.rawValue, 1)
        XCTAssertEqual(PlaceCategory.cafe.rawValue, 2)
        XCTAssertEqual(PlaceCategory.scenery.rawValue, 3)
        XCTAssertEqual(PlaceCategory.shopping.rawValue, 4)
        XCTAssertEqual(PlaceCategory.show.rawValue, 5)
        XCTAssertEqual(PlaceCategory.stay.rawValue, 6)
        XCTAssertEqual(PlaceCategory.allCases.count, 7)
    }

    func testLabels() {
        XCTAssertEqual(PlaceCategory.other.label, "其他")
        XCTAssertEqual(PlaceCategory.food.label, "美食")
        XCTAssertEqual(PlaceCategory.cafe.label, "咖啡甜品")
        XCTAssertEqual(PlaceCategory.scenery.label, "景点公园")
        XCTAssertEqual(PlaceCategory.shopping.label, "逛街")
        XCTAssertEqual(PlaceCategory.show.label, "影展演出")
        XCTAssertEqual(PlaceCategory.stay.label, "住宿")
    }

    func testFromRawFallsBackToOther() {
        XCTAssertEqual(PlaceCategory.from(raw: 3), .scenery)
        XCTAssertEqual(PlaceCategory.from(raw: 99), .other)   // 未知值兜底，存量 0 也归其他
        XCTAssertEqual(PlaceCategory.from(raw: -1), .other)
    }
}
