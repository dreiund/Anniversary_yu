import SwiftUI

/// 进程级服务：只初始化一次（static let 天然防重）。
enum AppServices {
    static let historyMonitor: HistoryMonitor = {
        let controller = PersistenceController.shared
        let monitor = HistoryMonitor(
            container: controller.container,
            localAuthor: PersistenceController.localTransactionAuthor,
            notifier: LocalNotifier(),
            isEnabled: { (UserDefaults.standard.object(forKey: "newMomentAlertOn") as? Bool) ?? true },
            myPartnerID: { backgroundContext in
                // 闭包在 monitor 的后台队列执行，只能用传入的 context——严禁碰 viewContext
                let repo = CoupleRepository(context: backgroundContext)
                guard let couple = try? repo.fetchCouple() else { return nil }
                return repo.currentPartnerID(of: couple)
            })
        monitor.start()
        return monitor
    }()
}

@main
struct AnniversaryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let persistence = PersistenceController.shared

    init() {
        _ = AppServices.historyMonitor
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }
    }
}
