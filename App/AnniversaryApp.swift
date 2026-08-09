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
            isLedgerEnabled: { (UserDefaults.standard.object(forKey: "newLedgerAlertOn") as? Bool) ?? true },
            isCycleEnabled: { (UserDefaults.standard.object(forKey: "cycleStartAlertOn") as? Bool) ?? true },
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
    @Environment(\.scenePhase) private var scenePhase
    private let persistence = PersistenceController.shared

    init() {
        _ = AppServices.historyMonitor
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--seed-map-demo") {
            DebugSeeder.seedMapDemoIfEmpty(context: persistence.viewContext)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }
        // P6-B1:第二道保险——accept 成功回调是第一道，App 前台激活时再兜底扫一遍
        // (冷启动首次变 active、每次从后台回前台都会触发；pruneEmptyLocalCouple 本身幂等，
        // 反复调用无副作用)。
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            try? CoupleRepository(context: persistence.viewContext).pruneEmptyLocalCouple()
        }
    }
}
