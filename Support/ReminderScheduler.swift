import UserNotifications

/// 本地提醒（spec ⑥ §五）：排程/取消都发生在操作设备；标题=事项主题。
enum ReminderPlanner {
    static func todoID(_ id: UUID) -> String { "todo-\(id.uuidString.lowercased())" }
    static func planID(_ id: UUID) -> String { "plan-\(id.uuidString.lowercased())" }
    static func shouldSchedule(remindAt: Date?, now: Date) -> Bool {
        guard let remindAt else { return false }
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
}
