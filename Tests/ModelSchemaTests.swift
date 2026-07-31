import XCTest
import CoreData
@testable import Anniversary

final class ModelSchemaTests: XCTestCase {
    let model = ModelSchema.model

    func testAllEntitiesPresent() {
        let names = Set(model.entities.compactMap(\.name))
        let expected: Set<String> = [
            "CDCouple", "CDPartner", "CDMeeting", "CDDateDay", "CDMoment",
            "CDPhoto", "CDEvaluation", "CDPlace", "CDDailyMood", "CDLedgerEntry",
            "CDEvidence", "CDCycle", "CDCycleDayLog", "CDIntimacyRecord", "CDPlanItem",
        ]
        XCTAssertEqual(names, expected)
    }

    func testCloudKitConstraint_AllRelationshipsOptional() {
        for entity in model.entities {
            for (name, rel) in entity.relationshipsByName {
                XCTAssertTrue(rel.isOptional, "\(entity.name ?? "?").\(name) 必须 optional（CloudKit 约束）")
            }
        }
    }

    func testCloudKitConstraint_NonOptionalAttributesHaveDefaults() {
        for entity in model.entities {
            for (name, attr) in entity.attributesByName where !attr.isOptional {
                XCTAssertNotNil(attr.defaultValue, "\(entity.name ?? "?").\(name) 非 optional 必须有默认值（CloudKit 约束）")
            }
        }
    }

    func testCloudKitConstraint_NoUniqueConstraints_NoOrderedRelationships() {
        for entity in model.entities {
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty, "\(entity.name ?? "?") 不得有 unique constraint")
            for (name, rel) in entity.relationshipsByName {
                XCTAssertFalse(rel.isOrdered, "\(entity.name ?? "?").\(name) 不得是 ordered relationship")
            }
        }
    }

    func testAllRelationshipsHaveInverses() {
        for entity in model.entities {
            for (name, rel) in entity.relationshipsByName {
                XCTAssertNotNil(rel.inverseRelationship, "\(entity.name ?? "?").\(name) 缺少 inverse")
            }
        }
    }

    func testImageBlobsUseExternalStorage() {
        let photo = model.entitiesByName["CDPhoto"]!
        let evidence = model.entitiesByName["CDEvidence"]!
        let partner = model.entitiesByName["CDPartner"]!
        XCTAssertTrue(photo.attributesByName["imageData"]!.allowsExternalBinaryDataStorage)
        XCTAssertTrue(evidence.attributesByName["imageData"]!.allowsExternalBinaryDataStorage)
        XCTAssertTrue(partner.attributesByName["avatarData"]!.allowsExternalBinaryDataStorage)
    }

    func testObjectGraphSaveAndFetchRoundTrip() throws {
        let container = NSPersistentContainer(name: "RoundTrip", managedObjectModel: model)
        let desc = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)
        let ctx = container.viewContext

        let couple = CDCouple(context: ctx)
        couple.id = UUID()
        couple.createdAt = Date()

        let meeting = CDMeeting(context: ctx)
        meeting.id = UUID()
        meeting.index = 7
        meeting.city = "上海"
        meeting.statusRaw = MeetingStatus.ongoing.rawValue
        meeting.couple = couple

        let day = CDDateDay(context: ctx)
        day.id = UUID()
        day.dayIndex = 1
        day.openedAt = Date()
        day.meeting = meeting

        let moment = CDMoment(context: ctx)
        moment.id = UUID()
        moment.title = "蟹家大院"
        moment.typeRaw = MomentType.restaurant.rawValue
        moment.happenedAt = Date()
        moment.dateDay = day

        let eval = CDEvaluation(context: ctx)
        eval.id = UUID()
        eval.stars = 5
        eval.moodEmoji = "😋"
        eval.comment = "秃黄油拌饭封神"
        eval.moment = moment

        let plan = CDPlanItem(context: ctx)
        plan.id = UUID()
        plan.title = "G102 高铁"
        plan.isDone = true
        plan.meeting = meeting

        try ctx.save()

        let fetched = try ctx.fetch(CDMoment.fetchRequest()) as! [CDMoment]
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.dateDay?.meeting?.city, "上海")
        XCTAssertEqual((fetched.first?.evaluations as? Set<CDEvaluation>)?.count, 1)
        let plans = try ctx.fetch(CDPlanItem.fetchRequest()) as! [CDPlanItem]
        XCTAssertEqual(plans.first?.meeting?.id, meeting.id)
    }

    func testPartnerHasRoleIndexWithDefault() {
        let partner = model.entitiesByName["CDPartner"]!
        let attr = partner.attributesByName["roleIndex"]
        XCTAssertNotNil(attr)
        XCTAssertFalse(attr!.isOptional)
        XCTAssertEqual(attr!.defaultValue as? Int16, 0)
    }
}
