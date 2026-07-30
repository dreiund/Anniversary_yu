import XCTest
@testable import Anniversary

final class DomainEnumTests: XCTestCase {
    func testRawValuesAreStable() {
        XCTAssertEqual(MeetingStatus.planned.rawValue, 0)
        XCTAssertEqual(MeetingStatus.ongoing.rawValue, 1)
        XCTAssertEqual(MeetingStatus.finished.rawValue, 2)

        XCTAssertEqual(MomentType.restaurant.rawValue, 0)
        XCTAssertEqual(MomentType.sight.rawValue, 1)
        XCTAssertEqual(MomentType.activity.rawValue, 2)
        XCTAssertEqual(MomentType.stay.rawValue, 3)
        XCTAssertEqual(MomentType.other.rawValue, 4)

        XCTAssertEqual(LedgerCategory.praise.rawValue, 0)
        XCTAssertEqual(LedgerCategory.complaint.rawValue, 1)
        XCTAssertEqual(LedgerCategory.like.rawValue, 2)
        XCTAssertEqual(LedgerCategory.trigger.rawValue, 3)

        XCTAssertEqual(EntryVisibility.sharedImmediately.rawValue, 0)
        XCTAssertEqual(EntryVisibility.privateUntilRevealed.rawValue, 1)

        XCTAssertEqual(FlowLevel.veryHeavy.rawValue, 4)
        XCTAssertEqual(PainLevel.severe.rawValue, 3)
        XCTAssertEqual(CycleColor.other.rawValue, 4)
    }

    func testChineseTitles() {
        XCTAssertEqual(MomentType.restaurant.title, "餐厅")
        XCTAssertEqual(LedgerCategory.trigger.title, "雷区")
        XCTAssertEqual(FlowLevel.medium.title, "中")
        XCTAssertEqual(PainLevel.mild.title, "轻")
        XCTAssertEqual(CycleColor.brightRed.title, "鲜红")
    }
}
