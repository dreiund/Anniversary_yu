import CoreData

/// 小本本仓库（spec §三/§六/§七）。可见性变更只走 reveal，update 永不碰——不可撤回由此保证。
struct LedgerRepository {
    let context: NSManagedObjectContext

    @discardableResult
    func createEntry(couple: CDCouple, category: LedgerCategory, title: String, detail: String?,
                     happenedAt: Date, visibility: EntryVisibility, place: CDPlace?,
                     evidenceDatas: [Data], authorID: UUID?) throws -> CDLedgerEntry {
        let entry = CDLedgerEntry(context: context)
        entry.id = UUID()
        entry.categoryRaw = category.rawValue
        entry.title = title
        entry.detail = detail
        entry.happenedAt = happenedAt
        entry.visibilityRaw = visibility.rawValue
        entry.createdAt = Date()
        entry.authorPartnerID = authorID
        entry.couple = couple
        entry.place = place
        appendEvidences(to: entry, datas: evidenceDatas, startAt: 0)
        try context.save()
        return entry
    }

    func updateEntry(_ entry: CDLedgerEntry, category: LedgerCategory, title: String,
                     detail: String?, happenedAt: Date, place: CDPlace?) throws {
        entry.categoryRaw = category.rawValue
        entry.title = title
        entry.detail = detail
        entry.happenedAt = happenedAt
        entry.place = place
        try context.save()
    }

    /// 公开给 TA：一次性动作（spec §三.2）。revealedAt 已存在则不动——时戳留痕且不可撤回。
    func reveal(_ entry: CDLedgerEntry, at date: Date) throws {
        guard entry.revealedAt == nil else { return }
        entry.revealedAt = date
        try context.save()
    }

    func addEvidences(_ entry: CDLedgerEntry, datas: [Data]) throws {
        let start = (evidencesSorted(entry).last?.sortIndex).map { $0 + 1 } ?? 0
        appendEvidences(to: entry, datas: datas, startAt: start)
        try context.save()
    }

    func deleteEvidence(_ evidence: CDEvidence) throws {
        context.delete(evidence)
        try context.save()
    }

    func delete(_ entry: CDLedgerEntry) throws {
        context.delete(entry)
        try context.save()
    }

    func evidencesSorted(_ entry: CDLedgerEntry) -> [CDEvidence] {
        ((entry.evidences as? Set<CDEvidence>) ?? [])
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    private func appendEvidences(to entry: CDLedgerEntry, datas: [Data], startAt: Int32) {
        for (i, data) in datas.enumerated() {
            let evidence = CDEvidence(context: context)
            evidence.id = UUID()
            evidence.imageData = data
            evidence.thumbnailData = Thumbnailer.thumbnailData(from: data)
            evidence.sortIndex = startAt + Int32(i)
            evidence.ledgerEntry = entry
        }
    }
}
