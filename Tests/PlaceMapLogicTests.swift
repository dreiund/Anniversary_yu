import XCTest
@testable import Anniversary

final class PlaceMapLogicTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    func testFarApartStayPins() {
        let out = MapClusterer.cluster([
            ClusterInput(id: a, point: CGPoint(x: 0, y: 0)),
            ClusterInput(id: b, point: CGPoint(x: 200, y: 0)),
        ], threshold: 44)
        XCTAssertEqual(out, [.pin(id: a, point: CGPoint(x: 0, y: 0)),
                             .pin(id: b, point: CGPoint(x: 200, y: 0))])
    }

    func testCloseItemsMergeIntoCentroidCluster() {
        let out = MapClusterer.cluster([
            ClusterInput(id: a, point: CGPoint(x: 0, y: 0)),
            ClusterInput(id: b, point: CGPoint(x: 30, y: 0)),
            ClusterInput(id: c, point: CGPoint(x: 30, y: 30)),
        ], threshold: 44)
        XCTAssertEqual(out.count, 1)
        guard case let .cluster(ids, point) = out[0] else { return XCTFail("应为聚合") }
        XCTAssertEqual(Set(ids), Set([a, b, c]))
        XCTAssertEqual(point.x, 20, accuracy: 0.01)   // 质心
        XCTAssertEqual(point.y, 10, accuracy: 0.01)
    }

    func testThresholdBoundaryStaysSeparate() {
        let out = MapClusterer.cluster([
            ClusterInput(id: a, point: CGPoint(x: 0, y: 0)),
            ClusterInput(id: b, point: CGPoint(x: 44.1, y: 0)),
        ], threshold: 44)
        XCTAssertEqual(out.count, 2)
    }

    func testVisitCountDedupsDateDays() {
        let d1 = UUID(), d2 = UUID()
        XCTAssertEqual(PlaceStats.visitCount(dateDayIDs: [d1, d1, d2, nil]), 2)
        XCTAssertEqual(PlaceStats.visitCount(dateDayIDs: []), 0)
    }

    func testAverageStars() {
        XCTAssertNil(PlaceStats.average([]))
        XCTAssertEqual(PlaceStats.average([4, 5])!, 4.5, accuracy: 0.001)
        XCTAssertEqual(PlaceStats.average([5])!, 5.0, accuracy: 0.001)
    }
}
