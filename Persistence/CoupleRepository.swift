import CoreData

struct CoupleRepository {
    let context: NSManagedObjectContext
    /// 注入以便单测隔离(参照 HistoryMonitor 的同款 defaults 注入)；生产全部走 .standard。
    var defaults: UserDefaults = .standard

    /// 本机若曾在 bootstrapIfNeeded 里就地新建过 couple，把它的 id 记在这——
    /// pruneEmptyLocalCouple 的自愈判据用它，而不是直接判空（原因见该方法注释）。
    static let locallyBootstrappedCoupleIDKey = "locallyBootstrappedCoupleID"

    /// P6-B1:多 couple 并存时确定性选择——共享 store 里的优先(配对完成语义强，
    /// 是参与者设备的真实身份来源),同 store 内按 createdAt 最早。这是 repo 层的完整歧义
    /// 消解语义(P2 双 couple 事故防线)。全仓视图层大量直接用的 `couples.first`
    /// (@FetchRequest<CDCouple>)只补了 createdAt 排序，保证"多次渲染/多处读取不再随机跳"，
    /// 拿不到"共享 store 优先"这层语义——SwiftUI FetchRequest 的 sortDescriptors 声明不了
    /// persistentStore 归属，这层判断只有拿得到 NSManagedObjectID 的 repo 层能做。过渡窗口内
    /// 两者理论上仍可能给出不同答案，靠 pruneEmptyLocalCouple 尽快把冗余那份收敛掉。单 couple
    /// 场景直接短路返回，行为与改动前完全一致。
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
    /// 直接用 `couples.first` 而不经 fetchCouple() 的地方重新踩回 P2 的身份随机坑。
    ///
    /// 判据是「本机创建标记」，不是「判空」本身——评审裁决:私有 store 同样挂了 CloudKit 同步，
    /// 换机/重装后 couple 记录先到、meetings/moments 等子数据还在路上的窗口里，一个正在同步、
    /// 迟早会有数据的**真实** couple 在这个瞬间跟空壳长得一模一样；这个窗口没有硬上限（CloudKit
    /// 导入顺序不保证——PlacePruner 已经因为同一原因放弃启动清扫，见其注释），任何「先等一会再
    /// 判空」的去抖都只是把误删概率调低、调不到零，且一旦真删错了还会把删除同步回云端（同款
    /// R7 事故模式）。本机创建标记从结构上排除了这种可能：远端同步落地的 couple 从来不会被
    /// 写进这个标记——标记只在 bootstrapIfNeeded 真正新建 couple 那一刻由本机写入——所以只删
    /// 「id 精确等于标记」的那一个，天生不会牵连任何正在同步中的真实 couple；标记缺失（老安装、
    /// 或从未在本机 bootstrap 过）时整体不做任何删除，宁可留着可疑冗余也不猜。isParticipantDevice
    /// 判断是双保险，非必要（标记只可能指向私有 store 里由本机创建的 couple）。删除成功后清掉
    /// 标记。幂等：无标记、标记指向的 couple 已被删、或它现在有数据了，都是 no-op。
    @discardableResult
    func pruneEmptyLocalCouple() throws -> Int {
        let request = CDCouple.fetchRequest()
        let all = (try context.fetch(request) as? [CDCouple]) ?? []
        guard all.count > 1,
              let markedIDString = defaults.string(forKey: Self.locallyBootstrappedCoupleIDKey),
              let markedID = UUID(uuidString: markedIDString),
              let marked = all.first(where: { $0.id == markedID }),
              !isParticipantDevice(marked),
              !hasAnyData(marked)
        else { return 0 }

        context.delete(marked)
        try context.save()
        defaults.removeObject(forKey: Self.locallyBootstrappedCoupleIDKey)
        return 1
    }

    /// 判空覆盖 couple 名下全部子关系——不止 brief 点名的 meetings/entries/todos/cycles 四类，
    /// 还核对了 places/dailyMoods/intimacyRecords 三类(覆盖更宽只会让判定更保守、更不容易删，
    /// 不会引入误删)。moments 不单独查：它是 meeting→dateDay→moment 派生的三级子关系，
    /// 结构上不可能在 meetings 为空时非空(没有 meeting 就没有能挂它的 dateDay)，单独查是死代码。
    private func hasAnyData(_ couple: CDCouple) -> Bool {
        let meetings = (couple.meetings as? Set<CDMeeting>) ?? []
        let places = (couple.places as? Set<CDPlace>) ?? []
        let dailyMoods = (couple.dailyMoods as? Set<CDDailyMood>) ?? []
        let ledgerEntries = (couple.ledgerEntries as? Set<CDLedgerEntry>) ?? []
        let cycles = (couple.cycles as? Set<CDCycle>) ?? []
        let intimacyRecords = (couple.intimacyRecords as? Set<CDIntimacyRecord>) ?? []
        let todos = (couple.todos as? Set<CDTodoItem>) ?? []
        return !meetings.isEmpty || !places.isEmpty || !dailyMoods.isEmpty
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
        // P6-B1:只有这里、真正新建 couple 时才落标记——早退返回既有 couple 的分支不碰它，
        // 标记必须精确对应「本机刚刚就地建的那一个」，pruneEmptyLocalCouple 靠它辨认冗余。
        defaults.set(couple.id?.uuidString, forKey: Self.locallyBootstrappedCoupleIDKey)
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
