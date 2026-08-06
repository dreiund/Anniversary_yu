import Foundation

/// 小本本筛选四档（spec §三.4）
enum LedgerFilter: CaseIterable {
    case all, theirs, mine, privateBox

    var label: String {
        switch self {
        case .all: return "全部"
        case .theirs: return "TA 记的"
        case .mine: return "我记的"
        case .privateBox: return "私密箱"
        }
    }
}

/// 小本本行为规则纯函数（spec §三）。Core Data 无关，单测直调。
enum LedgerRules {
    /// 只有作者能改删；身份缺失一律不可改
    static func canEdit(authorID: UUID?, myID: UUID?) -> Bool {
        guard let authorID, let myID else { return false }
        return authorID == myID
    }

    /// 已公开 = 建时即公开，或私密后被 reveal（revealedAt 一旦置上不可逆）
    static func isRevealed(visibilityRaw: Int16, revealedAt: Date?) -> Bool {
        visibilityRaw == EntryVisibility.sharedImmediately.rawValue || revealedAt != nil
    }

    /// 我的条目恒可见；对方条目仅公开可见（列表 / 详情入口 / 通知判定三处共用，不得旁路）
    static func isVisible(authorID: UUID?, myID: UUID?, visibilityRaw: Int16, revealedAt: Date?) -> Bool {
        if let authorID, let myID, authorID == myID { return true }
        return isRevealed(visibilityRaw: visibilityRaw, revealedAt: revealedAt)
    }

    static func matches(filter: LedgerFilter, authorID: UUID?, myID: UUID?,
                        visibilityRaw: Int16, revealedAt: Date?) -> Bool {
        guard isVisible(authorID: authorID, myID: myID,
                        visibilityRaw: visibilityRaw, revealedAt: revealedAt) else { return false }
        let mine = authorID != nil && authorID == myID
        switch filter {
        case .all: return true
        case .theirs: return !mine
        case .mine: return mine
        case .privateBox:
            return mine && !isRevealed(visibilityRaw: visibilityRaw, revealedAt: revealedAt)
        }
    }
}
