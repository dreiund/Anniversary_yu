import CoreData

struct NewEvaluation {
    let stars: Int16
    let moodEmoji: String?
    let comment: String?
}

struct MomentRepository {
    let context: NSManagedObjectContext

    @discardableResult
    func create(in meeting: CDMeeting, type: MomentType, title: String, body: String?,
                happenedAt: Date, photoDatas: [Data], myEvaluation: NewEvaluation?,
                authorID: UUID?, place: CDPlace?) throws -> CDMoment {
        let day = try MeetingRepository(context: context).dayForRecord(in: meeting, at: happenedAt)

        let moment = CDMoment(context: context)
        moment.id = UUID()
        moment.typeRaw = type.rawValue
        moment.title = title
        moment.body = body
        moment.happenedAt = happenedAt
        moment.createdAt = Date()
        moment.authorPartnerID = authorID
        moment.dateDay = day
        moment.place = place

        for (i, data) in photoDatas.enumerated() {
            let photo = CDPhoto(context: context)
            photo.id = UUID()
            photo.imageData = data
            photo.thumbnailData = Thumbnailer.thumbnailData(from: data)
            photo.sortIndex = Int32(i)
            photo.moment = moment
        }

        if let ev = myEvaluation {
            let evaluation = CDEvaluation(context: context)
            evaluation.id = UUID()
            evaluation.authorPartnerID = authorID
            evaluation.stars = ev.stars
            evaluation.moodEmoji = ev.moodEmoji
            evaluation.comment = ev.comment
            evaluation.moment = moment
        }

        try context.save()
        return moment
    }

    func update(_ moment: CDMoment, type: MomentType, title: String, body: String?, happenedAt: Date) throws {
        moment.typeRaw = type.rawValue
        moment.title = title
        moment.body = body
        moment.happenedAt = happenedAt
        // 反馈③：改日期后按区间规则自动重归属；原天变空则清除（原实现归属不动，是被报的 bug）
        if let oldDay = moment.dateDay, let meeting = oldDay.meeting {
            let target = try MeetingRepository(context: context).dayForRecord(in: meeting, at: happenedAt)
            if target.objectID != oldDay.objectID {
                moment.dateDay = target
                MeetingRepository(context: context).pruneDayIfEmpty(oldDay, in: meeting)
            }
        }
        try context.save()
    }

    func delete(_ moment: CDMoment) throws {
        context.delete(moment)
        try context.save()
    }

    func move(_ moment: CDMoment, to day: CDDateDay) throws {
        let oldDay = moment.dateDay
        moment.dateDay = day
        if let oldDay, oldDay.objectID != day.objectID, let meeting = oldDay.meeting {
            MeetingRepository(context: context).pruneDayIfEmpty(oldDay, in: meeting)
        }
        try context.save()
    }

    /// 编辑模式追加照片：sortIndex 续接既有最大值，保持既有排序不变
    func addPhotos(_ moment: CDMoment, datas: [Data]) throws {
        let base = (photosSorted(moment).last?.sortIndex ?? -1) + 1
        for (i, data) in datas.enumerated() {
            let photo = CDPhoto(context: context)
            photo.id = UUID()
            photo.imageData = data
            photo.thumbnailData = Thumbnailer.thumbnailData(from: data)
            photo.sortIndex = base + Int32(i)
            photo.moment = moment
        }
        try context.save()
    }

    func deletePhoto(_ photo: CDPhoto) throws {
        context.delete(photo)
        try context.save()
    }

    /// 换/清地点。旧 CDPlace 不删（可能被其他记忆引用；地点档案与归并是 P3 范围）
    func setPlace(_ moment: CDMoment, place: CDPlace?) throws {
        moment.place = place
        try context.save()
    }

    func daysWithMoments(in meeting: CDMeeting) -> [(day: CDDateDay, moments: [CDMoment])]{
        let days = ((meeting.dateDays as? Set<CDDateDay>) ?? [])
            .sorted { $0.dayIndex < $1.dayIndex }
        return days.map { day in
            let ms = ((day.moments as? Set<CDMoment>) ?? [])
                .sorted { ($0.happenedAt ?? .distantPast) < ($1.happenedAt ?? .distantPast) }
            return (day, ms)
        }
    }

    func photosSorted(_ moment: CDMoment) -> [CDPhoto] {
        ((moment.photos as? Set<CDPhoto>) ?? [])
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func evaluation(of moment: CDMoment, by authorID: UUID?) -> CDEvaluation? {
        // CloudKit 禁 unique 约束，双端并发补评可产生同 (moment, author) 短暂重复；
        // 按 id 字典序取首条，保证两端渲染与 upsert 存在判定选择一致（同 T5 mood 惯用法）。
        ((moment.evaluations as? Set<CDEvaluation>) ?? [])
            .filter { $0.authorPartnerID == authorID }
            .sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
            .first
    }

    /// 补评/改评的唯一写入口：同 (moment, author) 存在则更新，否则创建。
    @discardableResult
    func upsertEvaluation(on moment: CDMoment, by authorID: UUID?, _ new: NewEvaluation) throws -> CDEvaluation {
        let evaluation: CDEvaluation
        if let existing = self.evaluation(of: moment, by: authorID) {
            evaluation = existing
        } else {
            evaluation = CDEvaluation(context: context)
            evaluation.id = UUID()
            evaluation.authorPartnerID = authorID
            evaluation.moment = moment
        }
        evaluation.stars = new.stars
        evaluation.moodEmoji = new.moodEmoji
        evaluation.comment = new.comment
        try context.save()
        return evaluation
    }
}
