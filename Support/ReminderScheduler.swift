import UserNotifications

/// 本地提醒（spec ⑥ §五）：排程/取消都发生在操作设备；标题=事项主题。
enum ReminderPlanner {
    static func todoID(_ id: UUID) -> String { "todo-\(id.uuidString.lowercased())" }
    static func planID(_ id: UUID) -> String { "plan-\(id.uuidString.lowercased())" }
    /// isDone：完成的事项不该再响（P6-B3，堵「勾掉后编辑保存复活提醒」）——
    /// 勾掉只取消了当次已排程的通知，item/todo 的 remindAt 字段本身没清，
    /// 编辑表单随手保存时若不挡在这里，会让已完成事项的提醒被重新排程。
    static func shouldSchedule(remindAt: Date?, isDone: Bool, now: Date) -> Bool {
        guard let remindAt, !isDone else { return false }
        return remindAt > now
    }
}

enum ReminderScheduler {
    static func schedule(id: String, title: String, body: String, at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.removePendingNotificationRequests(withIdentifiers: [id])
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    static func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// 批量取消日程提醒（删除路径统一入口，spec §五「删除条目→取消」）：
    /// 调用方须在删除保存前收集受影响 CDPlanItem 的 id，删除保存后再传入本函数。
    static func cancelPlans(_ ids: [UUID]) {
        ids.forEach { cancel(id: ReminderPlanner.planID($0)) }
    }
}
