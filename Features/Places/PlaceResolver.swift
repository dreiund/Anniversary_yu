import CoreData

/// PickedPlace → CDPlace 共用解析（spec §七归并语义）：优先关联既有，否则六字段新建。
/// couple 挂接仅在既有归属为空时补（不动别人家的地点归属）。
enum PlaceResolver {
    static func resolve(_ picked: PickedPlace, context: NSManagedObjectContext,
                        couple: CDCouple?) -> CDPlace? {
        if let id = picked.existingPlaceID {
            let req = NSFetchRequest<CDPlace>(entityName: "CDPlace")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            req.fetchLimit = 1
            if let existing = (try? context.fetch(req))?.first {
                if existing.couple == nil { existing.couple = couple }
                return existing
            }
        }
        let place = CDPlace(context: context)
        place.id = UUID()
        place.name = picked.name
        place.latitude = picked.latitude
        place.longitude = picked.longitude
        place.categoryRaw = picked.categoryRaw
        place.createdAt = Date()
        place.couple = couple
        return place
    }
}
