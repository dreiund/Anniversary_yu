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
        let day = try MeetingRepository(context: context).dayForNewRecord(in: meeting, at: happenedAt)

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
        try context.save()
    }

    func delete(_ moment: CDMoment) throws {
        context.delete(moment)
        try context.save()
    }

    func move(_ moment: CDMoment, to day: CDDateDay) throws {
        moment.dateDay = day
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
        ((moment.evaluations as? Set<CDEvaluation>) ?? [])
            .first { $0.authorPartnerID == authorID }
    }
}
