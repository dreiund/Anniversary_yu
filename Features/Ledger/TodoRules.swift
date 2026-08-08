import Foundation

/// 记得做规则（spec ⑥ §二）：可见性与小本本同构；编辑删除仅作者；勾选=作者或 assignee
enum TodoRules {
    static func isVisible(authorID: UUID?, myID: UUID?, visibilityRaw: Int16, revealedAt: Date?) -> Bool {
        if authorID == myID { return true }
        return LedgerRules.isRevealed(visibilityRaw: visibilityRaw, revealedAt: revealedAt)
    }

    static func canEdit(authorID: UUID?, myID: UUID?) -> Bool {
        authorID != nil && authorID == myID
    }

    static func canToggleDone(authorID: UUID?, assigneeID: UUID?, myID: UUID?) -> Bool {
        guard myID != nil else { return false }
        return authorID == myID || assigneeID == myID
    }

    /// 未完成在前按 dueAt 升序（nil 最后）；已完成沉底按 doneAt 降序
    static func sortKey(isDone: Bool, dueAt: Date?, doneAt: Date?) -> (Int, Double) {
        if isDone {
            return (1, -(doneAt?.timeIntervalSince1970 ?? 0))
        }
        return (0, dueAt?.timeIntervalSince1970 ?? .greatestFiniteMagnitude)
    }
}
