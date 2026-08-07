import UserNotifications

struct LocalNotifier: MomentNotifying {
    func notifyNewMoments(titles: [String]) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "TA 记了新回忆"
            content.body = titles.count == 1
                ? "「\(titles[0])」 · 补上你那一半评价"
                : "\(titles.count) 条新回忆 · 补上你那一半评价"
            content.sound = .default
            let request = UNNotificationRequest(identifier: "new-moment-\(UUID().uuidString)",
                                                content: content, trigger: nil)
            center.add(request)
        }
    }

    func notifyNewLedgerEntries(count: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "TA 记了一条小本本"
            content.body = count == 1 ? "打开小本本看看" : "\(count) 条新记录 · 打开小本本看看"
            content.sound = .default
            let request = UNNotificationRequest(identifier: "new-ledger-\(UUID().uuidString)",
                                                content: content, trigger: nil)
            center.add(request)
        }
    }

    func notifyCycleStart() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "TA 记录了经期开始"
            content.body = "去她页看看"
            content.sound = .default
            let request = UNNotificationRequest(identifier: "cycle-start-\(UUID().uuidString)",
                                                content: content, trigger: nil)
            center.add(request)
        }
    }
}
