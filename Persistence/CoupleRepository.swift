import CoreData

struct CoupleRepository {
    let context: NSManagedObjectContext

    /// P6-B1:多 couple 并存时确定性选择——共享 store 里的优先(配对完成语义强，
    /// 是参与者设备的真实身份来源),同 store 内按 createdAt 最早;彻底告别无排序 fetch 的
    /// 随机首个(P2 双 couple 事故防线)。单 couple 场景直接短路返回，行为与改动前完全一致。
    /// "是否共享 store" 复用 isParticipantDevice 同一条纯文件名判定——不比较存活单例的
    /// persistentStore 实例(测试里常用独立 PersistenceController/NSPersistentContainer，
    /// 跟 PersistenceController.shared 是不同的 coordinator，实例比较永远不等)，任意
    /// context 下都正确、可测。
    func fetchCouple() throws -> CDCouple? {
        let request = CDCouple.fetchRequest()
        let all = (try context.fetch(request) as? [CDCouple]) ?? []
        guard all.count > 1 else { return all.first }
        return all.sorted { a, b in
            let aShared = isParticipantDevice(a)
            let bShared = isParticipantDevice(b)
            if aShared != bShared { return aShared }
            return (a.createdAt ?? .distantFuture) < (b.createdAt ?? .distantFuture)
        }.first
    }

    /// P6-B1:接受邀请成功 + App 前台激活时的自愈——私有 store 里如果混进「邀请没接受完就
    /// 先自己建了空间」的残留 couple，配对成功后它就是纯冗余：留着不仅碍事，还会让工程里大量
    /// 直接用 `couples.first`（FetchRequest 无排序）而不经 fetchCouple() 的地方
    /// （RootView/SettingsView 等）重新踩回 P2 的身份随机坑。
    /// 判空覆盖 couple 名下全部子数据（不止 brief 点名的 meetings/moments/entries/todos/cycles
    /// 五类，多查 places/dailyMoods/intimacyRecords 三类——覆盖更宽只会让判定更保守、更不容易删，
    /// 不会引入误删）。只删私有 store（非共享 store）里判空的 couple，共享 store 的 couple
    /// 永远不碰——它是 fetchCouple 的身份基准。只有本地 couple 总数 > 1 时才可能有冗余需要清理，
    /// 单 couple（含尚未配对的正常新用户）场景永不触碰，避免误删唯一、刚创建还没来得及填数据的
    /// 空间。幂等：多删一次也是 no-op。
    @discardableResult
    func pruneEmptyLocalCouple() throws -> Int {
        let request = CDCouple.fetchRequest()
        let all = (try context.fetch(request) as? [CDCouple]) ?? []
        guard all.count > 1 else { return 0 }

        var prunedCount = 0
        for couple in all where !isParticipantDevice(couple) && !hasAnyData(couple) {
            context.delete(couple)
            prunedCount += 1
        }
        if prunedCount > 0 { try context.save() }
        return prunedCount
    }

    private func hasAnyData(_ couple: CDCouple) -> Bool {
        let meetings = (couple.meetings as? Set<CDMeeting>) ?? []
        let moments = meetings.reduce(into: Set<CDMoment>()) { set, meeting in
            let dateDays = (meeting.dateDays as? Set<CDDateDay>) ?? []
            for day in dateDays { set.formUnion((day.moments as? Set<CDMoment>) ?? []) }
        }
        let places = (couple.places as? Set<CDPlace>) ?? []
        let dailyMoods = (couple.dailyMoods as? Set<CDDailyMood>) ?? []
        let ledgerEntries = (couple.ledgerEntries as? Set<CDLedgerEntry>) ?? []
        let cycles = (couple.cycles as? Set<CDCycle>) ?? []
        let intimacyRecords = (couple.intimacyRecords as? Set<CDIntimacyRecord>) ?? []
        let todos = (couple.todos as? Set<CDTodoItem>) ?? []
        return !meetings.isEmpty || !moments.isEmpty || !places.isEmpty || !dailyMoods.isEmpty
            || !ledgerEntries.isEmpty || !cycles.isEmpty || !intimacyRecords.isEmpty || !todos.isEmpty
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
