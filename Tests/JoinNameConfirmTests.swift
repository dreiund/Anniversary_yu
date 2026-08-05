import XCTest
@testable import Anniversary

final class JoinNameConfirmTests: XCTestCase {
    func testCreatorDeviceNeverNeedsConfirm() {
        XCTAssertFalse(JoinNameConfirm.isNeeded(isParticipantDevice: false,
                                                coupleID: UUID(), confirmedCoupleID: ""))
    }

    func testParticipantNeedsConfirmForNewCouple() {
        XCTAssertTrue(JoinNameConfirm.isNeeded(isParticipantDevice: true,
                                               coupleID: UUID(), confirmedCoupleID: ""))
    }

    func testParticipantSkipsWhenAlreadyConfirmed() {
        let id = UUID()
        XCTAssertFalse(JoinNameConfirm.isNeeded(isParticipantDevice: true,
                                                coupleID: id, confirmedCoupleID: id.uuidString))
    }

    func testNilCoupleIDNeverNeedsConfirm() {
        // id 缺失时若返回 true 会因确认动作写不进有效 id 而死循环卡在确认页
        XCTAssertFalse(JoinNameConfirm.isNeeded(isParticipantDevice: true,
                                                coupleID: nil, confirmedCoupleID: ""))
    }
}
