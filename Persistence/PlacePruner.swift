import CoreData

/// 孤儿地点清理（反馈⑥）：地点只随记忆/小本本创建，引用它们的记录删光后地点残留——
/// 足迹地图按「有记录才显示」过滤看不见，但选点地图/路线等直读 CDPlace 的地方还画着旧钉。
/// 删除类操作保存后调用；启动时也清扫一次（清历史遗留）。记忆/小本本/日程/记得做的挂靠也计入引用。
enum PlacePruner {
    static func pruneOrphans(context: NSManagedObjectContext) {
        guard let places = try? context.fetch(NSFetchRequest<CDPlace>(entityName: "CDPlace")) else { return }
        var pruned = false
        for place in places {
            let moments = ((place.moments as? Set<CDMoment>) ?? []).filter { !$0.isDeleted }
            let ledger = ((place.ledgerEntries as? Set<CDLedgerEntry>) ?? []).filter { !$0.isDeleted }
            let plans = ((place.planItems as? Set<CDPlanItem>) ?? []).filter { !$0.isDeleted }
            let todos = ((place.todoItems as? Set<CDTodoItem>) ?? []).filter { !$0.isDeleted }
            if moments.isEmpty, ledger.isEmpty, plans.isEmpty, todos.isEmpty {
                context.delete(place)
                pruned = true
            }
        }
        if pruned { try? context.save() }
    }
}
