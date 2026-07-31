import XCTest
import UIKit
@testable import Anniversary

final class ThumbnailerTests: XCTestCase {
    private func makeImageData(width: CGFloat, height: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { ctx in
            UIColor.systemRed.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    func testThumbnailDownsamplesLongEdgeTo600() throws {
        let original = makeImageData(width: 2000, height: 1000)

        let thumbData = try XCTUnwrap(Thumbnailer.thumbnailData(from: original))
        let thumb = try XCTUnwrap(UIImage(data: thumbData))

        let longEdge = max(thumb.size.width * thumb.scale, thumb.size.height * thumb.scale)
        XCTAssertLessThanOrEqual(longEdge, 600 + 1)
        XCTAssertLessThan(thumbData.count, original.count)
    }

    func testThumbnailReturnsNilForGarbage() {
        XCTAssertNil(Thumbnailer.thumbnailData(from: Data([0x00, 0x01, 0x02])))
    }
}
