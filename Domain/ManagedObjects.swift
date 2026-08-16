import CoreData

// 命名约定：authorPartnerID 是 CDPartner.id 的非关系引用（避免向 Partner 挂十几个 inverse；查询经 CoupleRepository）。
// to-many 统一为 NSSet?，读取时 `as? Set<CDX>` 后按 sortIndex / 时间排序。

@objc(CDCouple)
final class CDCouple: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var anniversaryDate: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var cycleLengthPref: Int16      // R20 经期设置:0=未设置(预测用 28/7 种子)
    @NSManaged var periodLengthPref: Int16
    @NSManaged var partners: NSSet?
    @NSManaged var meetings: NSSet?
    @NSManaged var places: NSSet?
    @NSManaged var dailyMoods: NSSet?
    @NSManaged var ledgerEntries: NSSet?
    @NSManaged var cycles: NSSet?
    @NSManaged var intimacyRecords: NSSet?
    @NSManaged var todos: NSSet?
}

extension CDCouple {
    /// 经期预测设置（R20-②:手动值始终生效;0=自动挡 → nil,引擎按记录均值、不足回落 28/7）
    var cyclePrefs: (cycleLength: Int?, periodLength: Int?) {
        (cycleLengthPref > 0 ? Int(cycleLengthPref) : nil,
         periodLengthPref > 0 ? Int(periodLengthPref) : nil)
    }
}

@objc(CDPartner)
final class CDPartner: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var avatarData: Data?
    @NSManaged var themeColorHex: String?
    @NSManaged var cloudUserID: String?
    @NSManaged var tracksCycle: Bool
    @NSManaged var roleIndex: Int16
    @NSManaged var couple: CDCouple?
}

@objc(CDMeeting)
final class CDMeeting: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var index: Int32
    @NSManaged var title: String?
    @NSManaged var city: String?
    @NSManaged var plannedStart: Date?
    @NSManaged var plannedEnd: Date?
    @NSManaged var startedAt: Date?
    @NSManaged var endedAt: Date?
    @NSManaged var statusRaw: Int16
    @NSManaged var coverPhotoID: UUID?
    @NSManaged var authorPartnerID: UUID?
    @NSManaged var visibilityRaw: Int16
    @NSManaged var revealedAt: Date?
    @NSManaged var couple: CDCouple?
    @NSManaged var dateDays: NSSet?
    @NSManaged var planItems: NSSet?
}

@objc(CDDateDay)
final class CDDateDay: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var dayIndex: Int32
    @NSManaged var openedAt: Date?
    @NSManaged var closedAt: Date?
    @NSManaged var meeting: CDMeeting?
    @NSManaged var moments: NSSet?
    @NSManaged var intimacyRecords: NSSet?
}

@objc(CDMoment)
final class CDMoment: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var typeRaw: Int16
    @NSManaged var title: String?
    @NSManaged var body: String?
    @NSManaged var happenedAt: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var authorPartnerID: UUID?
    @NSManaged var dateDay: CDDateDay?
    @NSManaged var place: CDPlace?
    @NSManaged var photos: NSSet?
    @NSManaged var evaluations: NSSet?
}

@objc(CDPhoto)
final class CDPhoto: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var imageData: Data?
    @NSManaged var thumbnailData: Data?
    @NSManaged var caption: String?
    @NSManaged var sortIndex: Int32
    @NSManaged var moment: CDMoment?
}

@objc(CDEvaluation)
final class CDEvaluation: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var authorPartnerID: UUID?
    @NSManaged var stars: Int16
    @NSManaged var moodEmoji: String?
    @NSManaged var comment: String?
    @NSManaged var moment: CDMoment?
}

@objc(CDPlace)
final class CDPlace: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var address: String?
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var categoryRaw: Int16
    @NSManaged var createdAt: Date?
    @NSManaged var couple: CDCouple?
    @NSManaged var moments: NSSet?
    @NSManaged var ledgerEntries: NSSet?
    @NSManaged var planItems: NSSet?
    @NSManaged var todoItems: NSSet?
}

@objc(CDDailyMood)
final class CDDailyMood: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var authorPartnerID: UUID?
    @NSManaged var day: Date?
    @NSManaged var moodEmoji: String?
    @NSManaged var note: String?
    @NSManaged var couple: CDCouple?
}

@objc(CDLedgerEntry)
final class CDLedgerEntry: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var categoryRaw: Int16
    @NSManaged var authorPartnerID: UUID?
    @NSManaged var title: String?
    @NSManaged var detail: String?
    @NSManaged var happenedAt: Date?
    @NSManaged var visibilityRaw: Int16
    @NSManaged var revealedAt: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var couple: CDCouple?
    @NSManaged var place: CDPlace?
    @NSManaged var evidences: NSSet?
}

@objc(CDEvidence)
final class CDEvidence: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var imageData: Data?
    @NSManaged var thumbnailData: Data?
    @NSManaged var sortIndex: Int32
    @NSManaged var ledgerEntry: CDLedgerEntry?
    @NSManaged var todoItem: CDTodoItem?
    @NSManaged var planItem: CDPlanItem?
}

@objc(CDCycle)
final class CDCycle: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var startDate: Date?
    @NSManaged var endDate: Date?
    @NSManaged var predictedStartAtLogging: Date?
    @NSManaged var authorPartnerID: UUID?
    @NSManaged var couple: CDCouple?
    @NSManaged var dayLogs: NSSet?
}

@objc(CDCycleDayLog)
final class CDCycleDayLog: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var day: Date?
    @NSManaged var flowRaw: Int16
    @NSManaged var painRaw: Int16
    @NSManaged var colorRaw: Int16
    @NSManaged var note: String?
    @NSManaged var cycle: CDCycle?
}

@objc(CDIntimacyRecord)
final class CDIntimacyRecord: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var happenedAt: Date?
    @NSManaged var protectionUsed: NSNumber?
    @NSManaged var note: String?
    @NSManaged var couple: CDCouple?
    @NSManaged var dateDay: CDDateDay?
}

@objc(CDPlanItem)
final class CDPlanItem: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var day: Date?
    @NSManaged var time: Date?
    @NSManaged var title: String?
    @NSManaged var note: String?
    @NSManaged var isDone: Bool
    @NSManaged var authorPartnerID: UUID?
    @NSManaged var sortIndex: Int32
    @NSManaged var placeText: String?
    @NSManaged var remindAt: Date?
    @NSManaged var visibilityRaw: Int16
    @NSManaged var revealedAt: Date?
    @NSManaged var meeting: CDMeeting?
    @NSManaged var place: CDPlace?
    @NSManaged var evidences: NSSet?
}

@objc(CDTodoItem)
final class CDTodoItem: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var detail: String?
    @NSManaged var dueAt: Date?
    @NSManaged var assigneePartnerID: UUID?
    @NSManaged var authorPartnerID: UUID?
    @NSManaged var visibilityRaw: Int16
    @NSManaged var revealedAt: Date?
    @NSManaged var isDone: Bool
    @NSManaged var doneAt: Date?
    @NSManaged var remindAt: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var couple: CDCouple?
    @NSManaged var place: CDPlace?
    @NSManaged var evidences: NSSet?
}

extension CDPlanItem: Identifiable {}
extension CDPlace: Identifiable {}
extension CDTodoItem: Identifiable {}
