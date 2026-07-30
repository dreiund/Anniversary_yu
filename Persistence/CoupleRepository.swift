import CoreData

struct CoupleRepository {
    let context: NSManagedObjectContext

    func fetchCouple() throws -> CDCouple? {
        let request = CDCouple.fetchRequest()
        request.fetchLimit = 1
        return try context.fetch(request).first as? CDCouple
    }

    @discardableResult
    func bootstrapIfNeeded(myName: String, partnerName: String, anniversary: Date?) throws -> CDCouple {
        if let existing = try fetchCouple() { return existing }

        let now = Date()
        let couple = CDCouple(context: context)
        couple.id = UUID()
        couple.createdAt = now
        couple.anniversaryDate = anniversary

        // 集合无序，themeColorHex 暂存"谁是创建者"：0=创建者/我，1=对方（P1 迁 roleIndex）
        let me = CDPartner(context: context)
        me.id = UUID()
        me.name = myName
        me.themeColorHex = "0"
        me.couple = couple

        let partner = CDPartner(context: context)
        partner.id = UUID()
        partner.name = partnerName
        partner.themeColorHex = "1"
        partner.couple = couple

        try context.save()
        return couple
    }

    /// [0]=创建者/我，[1]=对方（bootstrap 用 themeColorHex 暂存 "0"/"1" 作稳定序，
    /// P1 引入正式主题色时改为独立 roleIndex 属性）
    func partners(of couple: CDCouple) -> [CDPartner] {
        let set = (couple.partners as? Set<CDPartner>) ?? []
        return set.sorted { ($0.themeColorHex ?? "") < ($1.themeColorHex ?? "") }
    }
}
