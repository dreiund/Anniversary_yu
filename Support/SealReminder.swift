import CoreData
import UserNotifications

enum SealReminderDecision: Equatable {
    case schedule(Date)
    case cancel
}

enum SealReminderPlanner {
    /// spec §8-4：开着的约会日存在且开关开 → 下一个 23:30 提醒；否则取消。
    /// 恰在 23:30 触发时视为已过（> 而非 >=），排到次日。
    static func decision(hasOpenDay: Bool, enabled: Bool, now: Date, calendar: Calendar) -> SealReminderDecision {
        guard hasOpenDay, enabled else { return .cancel }
        var target = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: now)!
        if target <= now {
            target = calendar.date(byAdding: .day, value: 1, to: target)!
        }
        return .schedule(target)
    }
}

enum SealReminder {
    static let identifier = "seal-reminder-2330"

    /// 幂等对账：任何可能改变“开着的约会日”状态的动作之后调用一次，
    /// 按当前真实状态覆盖式重排或取消，不累积、不重复。
    static func refresh(context: NSManagedObjectContext, now: Date = Date()) {
        let enabled = (UserDefaults.standard.object(forKey: "sealReminderOn") as? Bool) ?? true
        let hasOpenDay: Bool = {
            guard let couple = try? CoupleRepository(context: context).fetchCouple() else { return false }
            let repo = MeetingRepository(context: context)
            guard let ongoing = try? repo.ongoingMeeting(couple: couple) else { return false }
            return ((try? repo.openDay(in: ongoing)) ?? nil) != nil
        }()

        let center = UNUserNotificationCenter.current()
        switch SealReminderPlanner.decision(hasOpenDay: hasOpenDay, enabled: enabled, now: now, calendar: .current) {
        case .cancel:
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
        case .schedule(let date):
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                let content = UNMutableNotificationContent()
                content.title = "今天到此为止？"
                content.body = "还开着约会日 · 睡前记得封盘"
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            }
        }
    }
}
