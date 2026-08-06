import XCTest
@testable import Anniversary

final class HistoryMonitorLedgerTests: XCTestCase {
    // spec §三.6/§九：对方的公开条目才提醒；私密插入不报；自己的不报
    func testLedgerNotifiable() {
        let shared = EntryVisibility.sharedImmediately.rawValue
        let priv = EntryVisibility.privateUntilRevealed.rawValue
        XCTAssertTrue(HistoryMonitor.ledgerNotifiable(authorIsMe: false, visibilityRaw: shared, revealedAt: nil))
        XCTAssertTrue(HistoryMonitor.ledgerNotifiable(authorIsMe: false, visibilityRaw: priv, revealedAt: Date()))
        XCTAssertFalse(HistoryMonitor.ledgerNotifiable(authorIsMe: false, visibilityRaw: priv, revealedAt: nil))
        XCTAssertFalse(HistoryMonitor.ledgerNotifiable(authorIsMe: true, visibilityRaw: shared, revealedAt: nil))
        XCTAssertFalse(HistoryMonitor.ledgerNotifiable(authorIsMe: true, visibilityRaw: priv, revealedAt: Date()))
    }
}
