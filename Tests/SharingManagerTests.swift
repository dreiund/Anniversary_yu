import XCTest
import CloudKit
@testable import Anniversary

final class SharingManagerTests: XCTestCase {
    private func makeShare() -> CKShare {
        CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
    }

    func testConfigureSetsTitleAndOpenPermission() {
        let share = makeShare()
        SharingManager.configure(share)
        XCTAssertEqual(share[CKShare.SystemFieldKey.title] as? String, "我们的纪念空间")
        XCTAssertEqual(share.publicPermission, .readWrite)
    }

    func testParticipantJoinedFalseForNilAndOwnerOnly() {
        XCTAssertFalse(SharingManager.participantJoined(in: nil))
        // 新建 share 只有 owner 一名参与者
        XCTAssertFalse(SharingManager.participantJoined(in: makeShare()))
    }
}
