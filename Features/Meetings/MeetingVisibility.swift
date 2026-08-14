import SwiftUI

/// R17 私密计划(spec §四):可见性判定与🔒标识——判定复用小本本口径,不造新函数
extension CDMeeting {
    /// 对 myID 是否可见:我的恒可见;对方的私密未公开不可见;旧数据(nil 作者/raw 0)恒可见
    func isVisible(to myID: UUID?) -> Bool {
        LedgerRules.isVisible(authorID: authorPartnerID, myID: myID,
                              visibilityRaw: visibilityRaw, revealedAt: revealedAt)
    }

    /// 私密且未公开(计划卡🔒chip / 表单锁定判定共用)
    var isPrivateUnrevealed: Bool {
        visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue && revealedAt == nil
    }
}

/// 「🔒 私密」小胶囊(计划卡/行前计划页头部共用;橙系沿用类别徽章的透明底范式,深浅色自适应)
struct MeetingPrivacyChip: View {
    var body: some View {
        Text("🔒 私密")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DS.dsOrange)
            .padding(.vertical, 2).padding(.horizontal, 8)
            .background(Capsule().fill(DS.dsOrange.opacity(0.14)))
    }
}
