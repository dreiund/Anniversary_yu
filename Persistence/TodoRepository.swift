import CoreData

struct TodoRepository {
    let context: NSManagedObjectContext

    @discardableResult
    func create(couple: CDCouple, title: String, detail: String?, dueAt: Date,
                assigneeID: UUID?, authorID: UUID?, visibility: EntryVisibility,
                place: CDPlace?, remindAt: Date?, calendar: Calendar) throws -> CDTodoItem {
        let todo = CDTodoItem(context: context)
        todo.id = UUID()
        todo.title = title
        todo.detail = detail
        todo.dueAt = calendar.startOfDay(for: dueAt)
        todo.assigneePartnerID = assigneeID
        todo.authorPartnerID = authorID
        todo.visibilityRaw = visibility.rawValue
        todo.place = place
        todo.remindAt = remindAt
        todo.createdAt = Date()
        todo.couple = couple
        try context.save()
        return todo
    }

    func update(_ todo: CDTodoItem, title: String, detail: String?, dueAt: Date,
                assigneeID: UUID?, place: CDPlace?, remindAt: Date?, calendar: Calendar) throws {
        todo.title = title
        todo.detail = detail
        todo.dueAt = calendar.startOfDay(for: dueAt)
        todo.assigneePartnerID = assigneeID
        todo.place = place
        todo.remindAt = remindAt
        try context.save()
    }

    func setDone(_ todo: CDTodoItem, done: Bool, at: Date) throws {
        todo.isDone = done
        todo.doneAt = done ? at : nil
        try context.save()
    }

    /// 公开仪式：一次性置戳（同小本本 reveal 语义），不碰 visibilityRaw
    func reveal(_ todo: CDTodoItem, at: Date) throws {
        guard todo.revealedAt == nil else { return }
        todo.revealedAt = at
        try context.save()
    }

    func delete(_ todo: CDTodoItem) throws {
        context.delete(todo)
        try context.save()
        PlacePruner.pruneOrphans(context: context)
    }

    func todos(couple: CDCouple) -> [CDTodoItem] {
        ((couple.todos as? Set<CDTodoItem>) ?? [])
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
}
