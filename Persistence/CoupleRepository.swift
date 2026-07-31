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

        let me = CDPartner(context: context)
        me.id = UUID()
        me.name = myName
        me.roleIndex = 0
        me.couple = couple

        let partner = CDPartner(context: context)
        partner.id = UUID()
        partner.name = partnerName
        partner.roleIndex = 1
        partner.couple = couple

        try context.save()
        return couple
    }

    /// [0]=创建者/我（roleIndex 0），[1]=对方（roleIndex 1）。保序硬约束，禁止更改排序键。
    func partners(of couple: CDCouple) -> [CDPartner] {
        let set = (couple.partners as? Set<CDPartner>) ?? []
        return set.sorted { $0.roleIndex < $1.roleIndex }
    }

    /// 创建者（单机阶段即"我"）的业务 ID，用作各类记录的 authorID
    func creatorID(of couple: CDCouple) -> UUID? {
        partners(of: couple).first?.id
    }
}
