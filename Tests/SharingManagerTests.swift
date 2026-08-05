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

    // spec §一 状态表：四态规则
    func testPairingStatusTable() {
        typealias S = SharingManager
        // 受邀方设备恒为已连接
        XCTAssertEqual(S.pairingStatus(shareExists: false, participantJoined: false,
                                       publicPermissionOpen: false, isParticipantDevice: true), .connected)
        // 无 share → 未配对
        XCTAssertEqual(S.pairingStatus(shareExists: false, participantJoined: false,
                                       publicPermissionOpen: true, isParticipantDevice: false), .notPaired)
        // 有参与者已接受 → 已连接（无论锁没锁）
        XCTAssertEqual(S.pairingStatus(shareExists: true, participantJoined: true,
                                       publicPermissionOpen: false, isParticipantDevice: false), .connected)
        // 无参与者 + 链接开着 → 邀请已发出
        XCTAssertEqual(S.pairingStatus(shareExists: true, participantJoined: false,
                                       publicPermissionOpen: true, isParticipantDevice: false), .invited)
        // 无参与者 + 已锁（解绑后遗留）→ 未配对
        XCTAssertEqual(S.pairingStatus(shareExists: true, participantJoined: false,
                                       publicPermissionOpen: false, isParticipantDevice: false), .notPaired)
    }

    func testPairingStatusLabels() {
        XCTAssertEqual(PairingStatus.notPaired.label, "未配对")
        XCTAssertEqual(PairingStatus.invited.label, "邀请已发出")
        XCTAssertEqual(PairingStatus.connected.label, "已连接")
    }
}
