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

    /// 本机是否为受邀加入的一方：创建方的 couple 永远在私有库文件里，
    /// 受邀方的 couple 只会经共享 zone 镜像进共享库文件。
    /// 纯数据判定——无本地旗标，删 App 重装后依然正确，可脱离 CloudKit 单测。
    func isParticipantDevice(_ couple: CDCouple) -> Bool {
        couple.objectID.persistentStore?.url?.lastPathComponent == PersistenceController.sharedStoreFileName
    }

    /// 本机使用者：创建方设备 = partners[0]，受邀方设备 = partners[1]。
    /// 全工程写 authorPartnerID 的唯一来源是 currentPartnerID(of:)。
    func currentPartner(of couple: CDCouple) -> CDPartner? {
        let list = partners(of: couple)
        if isParticipantDevice(couple) {
            return list.count > 1 ? list[1] : nil
        }
        return list.first
    }

    func otherPartner(of couple: CDCouple) -> CDPartner? {
        guard let mine = currentPartner(of: couple) else { return nil }
        return partners(of: couple).first { $0.objectID != mine.objectID }
    }

    func currentPartnerID(of couple: CDCouple) -> UUID? {
        currentPartner(of: couple)?.id
    }

    /// 已连接后 TA 的昵称只能 TA 自己改：受邀方永不可改对方；创建方在对方加入后不可改。
    /// 未配对/邀请未被接受时创建方可改两个名字（TA 本人还没进来，得能改错别字）。
    static func canEditPartnerName(isParticipantDevice: Bool, participantJoined: Bool) -> Bool {
        !isParticipantDevice && !participantJoined
    }
}
