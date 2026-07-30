import XCTest
@testable import Anniversary

final class DSTokenTests: XCTestCase {
    func testRGBComponentsParsesHex() {
        let c = rgbComponents(hex: 0xF5F5F7)
        XCTAssertEqual(c.r, 245.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(c.g, 245.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(c.b, 247.0 / 255.0, accuracy: 0.0001)
    }

    func testActionBlueComponents() {
        let c = rgbComponents(hex: 0x0066CC)
        XCTAssertEqual(c.r, 0, accuracy: 0.0001)
        XCTAssertEqual(c.g, 102.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(c.b, 204.0 / 255.0, accuracy: 0.0001)
    }
}
