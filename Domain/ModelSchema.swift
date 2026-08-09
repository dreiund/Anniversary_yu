import CoreData

enum ModelSchema {
    /// 进程内唯一模型实例（两个容器共用同一 model，避免重复实体注册警告）
    static let model: NSManagedObjectModel = makeModel()

    private static func makeModel() -> NSManagedObjectModel {
        // 属性
        func attr(
            _ name: String, _ type: NSAttributeType,
            optional: Bool = true, defaultValue: Any? = nil, external: Bool = false
        ) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = optional
            a.defaultValue = defaultValue
            a.allowsExternalBinaryDataStorage = external
            return a
        }

        func entity(_ name: String, _ cls: AnyClass, _ attrs: [NSAttributeDescription]) -> NSEntityDescription {
            let e = NSEntityDescription()
            e.name = name
            e.managedObjectClassName = NSStringFromClass(cls)
            e.properties = attrs
            return e
        }

        // 一对多 + 逆关系；cascade=true 表示删父删子
        func oneToMany(
            _ parent: NSEntityDescription, _ toMany: String,
            _ child: NSEntityDescription, _ toOne: String,
            cascade: Bool = true
        ) {
            let many = NSRelationshipDescription()
            many.name = toMany
            many.destinationEntity = child
            many.minCount = 0
            many.maxCount = 0
            many.isOptional = true
            many.deleteRule = cascade ? .cascadeDeleteRule : .nullifyDeleteRule

            let one = NSRelationshipDescription()
            one.name = toOne
            one.destinationEntity = parent
            one.minCount = 0
            one.maxCount = 1
            one.isOptional = true
            one.deleteRule = .nullifyDeleteRule

            many.inverseRelationship = one
            one.inverseRelationship = many
            parent.properties.append(many)
            child.properties.append(one)
        }

        let couple = entity("CDCouple", CDCouple.self, [
            attr("id", .UUIDAttributeType),
            attr("anniversaryDate", .dateAttributeType),
            attr("createdAt", .dateAttributeType),
        ])

        let partner = entity("CDPartner", CDPartner.self, [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("avatarData", .binaryDataAttributeType, external: true),
            attr("themeColorHex", .stringAttributeType),
            attr("cloudUserID", .stringAttributeType),
            attr("tracksCycle", .booleanAttributeType, optional: false, defaultValue: false),
            attr("roleIndex", .integer16AttributeType, optional: false, defaultValue: 0),
        ])

        let meeting = entity("CDMeeting", CDMeeting.self, [
            attr("id", .UUIDAttributeType),
            attr("index", .integer32AttributeType, optional: false, defaultValue: 0),
            attr("title", .stringAttributeType),
            attr("city", .stringAttributeType),
            attr("plannedStart", .dateAttributeType),
            attr("plannedEnd", .dateAttributeType),
            attr("startedAt", .dateAttributeType),
            attr("endedAt", .dateAttributeType),
            attr("statusRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("coverPhotoID", .UUIDAttributeType),
        ])

        let dateDay = entity("CDDateDay", CDDateDay.self, [
            attr("id", .UUIDAttributeType),
            attr("dayIndex", .integer32AttributeType, optional: false, defaultValue: 0),
            attr("openedAt", .dateAttributeType),
            attr("closedAt", .dateAttributeType),
        ])

        let moment = entity("CDMoment", CDMoment.self, [
            attr("id", .UUIDAttributeType),
            attr("typeRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("title", .stringAttributeType),
            attr("body", .stringAttributeType),
            attr("happenedAt", .dateAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("authorPartnerID", .UUIDAttributeType),
        ])

        let photo = entity("CDPhoto", CDPhoto.self, [
            attr("id", .UUIDAttributeType),
            attr("imageData", .binaryDataAttributeType, external: true),
            attr("thumbnailData", .binaryDataAttributeType),
            attr("caption", .stringAttributeType),
            attr("sortIndex", .integer32AttributeType, optional: false, defaultValue: 0),
        ])

        let evaluation = entity("CDEvaluation", CDEvaluation.self, [
            attr("id", .UUIDAttributeType),
            attr("authorPartnerID", .UUIDAttributeType),
            attr("stars", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("moodEmoji", .stringAttributeType),
            attr("comment", .stringAttributeType),
        ])

        let place = entity("CDPlace", CDPlace.self, [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("address", .stringAttributeType),
            attr("latitude", .doubleAttributeType, optional: false, defaultValue: 0.0),
            attr("longitude", .doubleAttributeType, optional: false, defaultValue: 0.0),
            attr("categoryRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("createdAt", .dateAttributeType),
        ])

        let dailyMood = entity("CDDailyMood", CDDailyMood.self, [
            attr("id", .UUIDAttributeType),
            attr("authorPartnerID", .UUIDAttributeType),
            attr("day", .dateAttributeType),
            attr("moodEmoji", .stringAttributeType),
            attr("note", .stringAttributeType),
        ])

        let ledger = entity("CDLedgerEntry", CDLedgerEntry.self, [
            attr("id", .UUIDAttributeType),
            attr("categoryRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("authorPartnerID", .UUIDAttributeType),
            attr("title", .stringAttributeType),
            attr("detail", .stringAttributeType),
            attr("happenedAt", .dateAttributeType),
            attr("visibilityRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("revealedAt", .dateAttributeType),
            attr("createdAt", .dateAttributeType),
        ])

        let evidence = entity("CDEvidence", CDEvidence.self, [
            attr("id", .UUIDAttributeType),
            attr("imageData", .binaryDataAttributeType, external: true),
            attr("thumbnailData", .binaryDataAttributeType),
            attr("sortIndex", .integer32AttributeType, optional: false, defaultValue: 0),
        ])

        let cycle = entity("CDCycle", CDCycle.self, [
            attr("id", .UUIDAttributeType),
            attr("startDate", .dateAttributeType),
            attr("endDate", .dateAttributeType),
            attr("predictedStartAtLogging", .dateAttributeType),
            attr("authorPartnerID", .UUIDAttributeType),
        ])

        let cycleLog = entity("CDCycleDayLog", CDCycleDayLog.self, [
            attr("id", .UUIDAttributeType),
            attr("day", .dateAttributeType),
            attr("flowRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("painRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("colorRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("note", .stringAttributeType),
        ])

        let intimacy = entity("CDIntimacyRecord", CDIntimacyRecord.self, [
            attr("id", .UUIDAttributeType),
            attr("happenedAt", .dateAttributeType),
            attr("protectionUsed", .booleanAttributeType),
            attr("note", .stringAttributeType),
        ])

        let planItem = entity("CDPlanItem", CDPlanItem.self, [
            attr("id", .UUIDAttributeType),
            attr("day", .dateAttributeType),
            attr("time", .dateAttributeType),
            attr("title", .stringAttributeType),
            attr("note", .stringAttributeType),
            attr("isDone", .booleanAttributeType, optional: false, defaultValue: false),
            attr("authorPartnerID", .UUIDAttributeType),
            attr("sortIndex", .integer32AttributeType, optional: false, defaultValue: 0),
            attr("placeText", .stringAttributeType),
            attr("remindAt", .dateAttributeType),
        ])

        let todo = entity("CDTodoItem", CDTodoItem.self, [
            attr("id", .UUIDAttributeType),
            attr("title", .stringAttributeType),
            attr("detail", .stringAttributeType),
            attr("dueAt", .dateAttributeType),
            attr("assigneePartnerID", .UUIDAttributeType),
            attr("authorPartnerID", .UUIDAttributeType),
            attr("visibilityRaw", .integer16AttributeType, optional: false, defaultValue: 0),
            attr("revealedAt", .dateAttributeType),
            attr("isDone", .booleanAttributeType, optional: false, defaultValue: false),
            attr("doneAt", .dateAttributeType),
            attr("remindAt", .dateAttributeType),
            attr("createdAt", .dateAttributeType),
        ])

        // 关系（父 → 子）
        oneToMany(couple, "partners", partner, "couple")
        oneToMany(couple, "meetings", meeting, "couple")
        oneToMany(couple, "places", place, "couple")
        oneToMany(couple, "dailyMoods", dailyMood, "couple")
        oneToMany(couple, "ledgerEntries", ledger, "couple")
        oneToMany(couple, "cycles", cycle, "couple")
        oneToMany(couple, "intimacyRecords", intimacy, "couple")
        oneToMany(couple, "todos", todo, "couple")
        oneToMany(meeting, "dateDays", dateDay, "meeting")
        oneToMany(meeting, "planItems", planItem, "meeting")
        oneToMany(dateDay, "moments", moment, "dateDay")
        oneToMany(dateDay, "intimacyRecords", intimacy, "dateDay", cascade: false)
        oneToMany(moment, "photos", photo, "moment")
        oneToMany(moment, "evaluations", evaluation, "moment")
        oneToMany(place, "moments", moment, "place", cascade: false)
        oneToMany(place, "ledgerEntries", ledger, "place", cascade: false)
        oneToMany(place, "planItems", planItem, "place", cascade: false)
        oneToMany(place, "todoItems", todo, "place", cascade: false)
        oneToMany(ledger, "evidences", evidence, "ledgerEntry")
        oneToMany(cycle, "dayLogs", cycleLog, "cycle")

        let model = NSManagedObjectModel()
        model.entities = [
            couple, partner, meeting, dateDay, moment, photo, evaluation, place,
            dailyMood, ledger, evidence, cycle, cycleLog, intimacy, planItem, todo,
        ]
        return model
    }
}
