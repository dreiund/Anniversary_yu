import XCTest
@testable import Anniversary

final class LedgerRulesTests: XCTestCase {
    private let me = UUID()
    private let ta = UUID()
    private let shared = EntryVisibility.sharedImmediately.rawValue
    private let priv = EntryVisibility.privateUntilRevealed.rawValue

    // spec §三.1：只有作者能改删；身份缺失一律不可改
    func testCanEdit() {
        XCTAssertTrue(LedgerRules.canEdit(authorID: me, myID: me))
        XCTAssertFalse(LedgerRules.canEdit(authorID: ta, myID: me))
        XCTAssertFalse(LedgerRules.canEdit(authorID: nil, myID: me))
        XCTAssertFalse(LedgerRules.canEdit(authorID: me, myID: nil))
        XCTAssertFalse(LedgerRules.canEdit(authorID: nil, myID: nil))
    }

    // 公开判定：公开可见性恒公开；私密以 revealedAt 为准（spec §三.2 不可撤回的判据）
    func testIsRevealed() {
        XCTAssertTrue(LedgerRules.isRevealed(visibilityRaw: shared, revealedAt: nil))
        XCTAssertFalse(LedgerRules.isRevealed(visibilityRaw: priv, revealedAt: nil))
        XCTAssertTrue(LedgerRules.isRevealed(visibilityRaw: priv, revealedAt: Date()))
    }

    // spec §三.3：我的恒可见；对方的仅公开可见
    func testIsVisible() {
        XCTAssertTrue(LedgerRules.isVisible(authorID: me, myID: me, visibilityRaw: priv, revealedAt: nil))
        XCTAssertTrue(LedgerRules.isVisible(authorID: ta, myID: me, visibilityRaw: shared, revealedAt: nil))
        XCTAssertTrue(LedgerRules.isVisible(authorID: ta, myID: me, visibilityRaw: priv, revealedAt: Date()))
        XCTAssertFalse(LedgerRules.isVisible(authorID: ta, myID: me, visibilityRaw: priv, revealedAt: nil))
    }

    // spec §三.4 四档筛选真值表
    func testFilterMatrix() {
        // 全部 = 可见全集（含我的私密，不含对方私密）
        XCTAssertTrue(LedgerRules.matches(filter: .all, authorID: me, myID: me, visibilityRaw: priv, revealedAt: nil))
        XCTAssertFalse(LedgerRules.matches(filter: .all, authorID: ta, myID: me, visibilityRaw: priv, revealedAt: nil))
        XCTAssertTrue(LedgerRules.matches(filter: .all, authorID: ta, myID: me, visibilityRaw: shared, revealedAt: nil))
        // TA 记的 = 作者为对方（天然只含公开）
        XCTAssertTrue(LedgerRules.matches(filter: .theirs, authorID: ta, myID: me, visibilityRaw: shared, revealedAt: nil))
        XCTAssertFalse(LedgerRules.matches(filter: .theirs, authorID: me, myID: me, visibilityRaw: shared, revealedAt: nil))
        XCTAssertFalse(LedgerRules.matches(filter: .theirs, authorID: ta, myID: me, visibilityRaw: priv, revealedAt: nil))
        // 我记的 = 作者为我（含私密）
        XCTAssertTrue(LedgerRules.matches(filter: .mine, authorID: me, myID: me, visibilityRaw: priv, revealedAt: nil))
        XCTAssertTrue(LedgerRules.matches(filter: .mine, authorID: me, myID: me, visibilityRaw: shared, revealedAt: nil))
        XCTAssertFalse(LedgerRules.matches(filter: .mine, authorID: ta, myID: me, visibilityRaw: shared, revealedAt: nil))
        // 私密箱 = 我的未公开
        XCTAssertTrue(LedgerRules.matches(filter: .privateBox, authorID: me, myID: me, visibilityRaw: priv, revealedAt: nil))
        XCTAssertFalse(LedgerRules.matches(filter: .privateBox, authorID: me, myID: me, visibilityRaw: priv, revealedAt: Date()))
        XCTAssertFalse(LedgerRules.matches(filter: .privateBox, authorID: me, myID: me, visibilityRaw: shared, revealedAt: nil))
        XCTAssertFalse(LedgerRules.matches(filter: .privateBox, authorID: ta, myID: me, visibilityRaw: priv, revealedAt: nil))
    }

    func testFilterLabels() {
        XCTAssertEqual(LedgerFilter.all.label, "全部")
        XCTAssertEqual(LedgerFilter.theirs.label, "TA 记的")
        XCTAssertEqual(LedgerFilter.mine.label, "我记的")
        XCTAssertEqual(LedgerFilter.privateBox.label, "私密箱")
    }
}
