import XCTest
import CoreData
@testable import Anniversary

final class TodoTests: XCTestCase {
    private var pc: PersistenceController!
    private var couple: CDCouple!
    private var repo: TodoRepository!
    private let me = UUID(), her = UUID()
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func d(_ day: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(day) * 86_400) }

    override func setUpWithError() throws {
        pc = PersistenceController(inMemory: true)
        couple = try CoupleRepository(context: pc.viewContext)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        repo = TodoRepository(context: pc.viewContext)
    }

    func testRulesVisibilityAndPermissions() {
        // 自己的私密恒可见；对方的私密不可见、公开可见
        XCTAssertTrue(TodoRules.isVisible(authorID: me, myID: me, visibilityRaw: 1, revealedAt: nil))
        XCTAssertFalse(TodoRules.isVisible(authorID: her, myID: me, visibilityRaw: 1, revealedAt: nil))
        XCTAssertTrue(TodoRules.isVisible(authorID: her, myID: me, visibilityRaw: 0, revealedAt: nil))
        XCTAssertTrue(TodoRules.isVisible(authorID: her, myID: me, visibilityRaw: 1, revealedAt: d(1)))
        XCTAssertTrue(TodoRules.canEdit(authorID: me, myID: me))
        XCTAssertFalse(TodoRules.canEdit(authorID: her, myID: me))
        XCTAssertTrue(TodoRules.canToggleDone(authorID: her, assigneeID: me, myID: me))   // 我是 assignee
        XCTAssertTrue(TodoRules.canToggleDone(authorID: me, assigneeID: her, myID: me))   // 我是作者
        XCTAssertFalse(TodoRules.canToggleDone(authorID: her, assigneeID: her, myID: me)) // 都不是
    }

    func testSortKeyOrdersOpenByDueThenDoneSinks() {
        let open1 = TodoRules.sortKey(isDone: false, dueAt: d(3), doneAt: nil)
        let open2 = TodoRules.sortKey(isDone: false, dueAt: d(5), doneAt: nil)
        let openNil = TodoRules.sortKey(isDone: false, dueAt: nil, doneAt: nil)
        let done = TodoRules.sortKey(isDone: true, dueAt: d(1), doneAt: d(9))
        XCTAssertTrue(open1 < open2)
        XCTAssertTrue(open2 < openNil)
        XCTAssertTrue(openNil < done)                              // 完成永远沉底
    }

    func testRepositoryCrudDoneReveal() throws {
        let todo = try repo.create(couple: couple, title: "带充电宝", detail: nil, dueAt: d(10),
                                   assigneeID: her, authorID: me, visibility: .privateUntilRevealed,
                                   place: nil, remindAt: nil, calendar: cal)
        XCTAssertEqual(todo.dueAt, cal.startOfDay(for: d(10)))
        XCTAssertEqual(todo.visibilityRaw, 1)
        XCTAssertNotNil(todo.createdAt)
        try repo.setDone(todo, done: true, at: d(11))
        XCTAssertTrue(todo.isDone)
        XCTAssertEqual(todo.doneAt, d(11))
        try repo.setDone(todo, done: false, at: d(12))
        XCTAssertFalse(todo.isDone)
        XCTAssertNil(todo.doneAt)
        try repo.reveal(todo, at: d(11))
        try repo.reveal(todo, at: d(12))
        XCTAssertEqual(todo.revealedAt, d(11))                     // 一次性
        try repo.update(todo, title: "带两个充电宝", detail: "白色那个", dueAt: d(12),
                        assigneeID: me, place: nil, remindAt: d(12), calendar: cal)
        XCTAssertEqual(todo.assigneePartnerID, me)
        XCTAssertEqual(todo.remindAt, d(12))
        try repo.delete(todo)
        XCTAssertTrue(repo.todos(couple: couple).isEmpty)
    }
}
