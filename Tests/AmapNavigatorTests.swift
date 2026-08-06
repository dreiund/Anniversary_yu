import XCTest
@testable import Anniversary

final class AmapNavigatorTests: XCTestCase {
    func testAmapURLComposition() throws {
        let url = try XCTUnwrap(AmapNavigator.amapURL(
            name: "一尺花园", latitude: 31.2304, longitude: 121.4737))
        XCTAssertEqual(url.scheme, "iosamap")
        XCTAssertEqual(url.host, "path")
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["dlat"], "31.2304")
        XCTAssertEqual(query["dlon"], "121.4737")
        XCTAssertEqual(query["dname"], "一尺花园")
        XCTAssertEqual(query["dev"], "0")            // 坐标已是 GCJ-02，高德不得再偏移
        XCTAssertEqual(query["sourceApplication"], "Anniversary")
    }

    func testChineseNameIsPercentEncodedInAbsoluteString() throws {
        let url = try XCTUnwrap(AmapNavigator.amapURL(
            name: "演示公园", latitude: 31, longitude: 121))
        XCTAssertFalse(url.absoluteString.contains("演示公园"))   // 原文不应裸露在 URL 里
        XCTAssertTrue(url.absoluteString.contains("dname="))
    }
}
