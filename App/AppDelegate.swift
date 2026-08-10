import UIKit
import CloudKit
import UserNotifications

/// SwiftUI 生命周期不暴露 CloudKit 分享接受回调，桥一层 UIKit delegate。
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// P6-B5：didFinishLaunching 是 UIKit 生命周期里最早能挂 delegate 的时机——
    /// 早于任何本地/远程通知可能送达，避免前台弹通知时因 delegate 还没挂上被系统默认吞掉。
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

/// P6-B5：App 前台时本地通知（封盘/待办/日程/经期/TA 新记）也可见——
/// 不实现这个方法时系统默认前台收到通知不出横幅/声音，用户会以为提醒没生效。
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// 热启动：App 在运行/后台时点开邀请链接
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        SharingManager.accept(cloudKitShareMetadata)
    }

    /// 冷启动：点链接把 App 拉起时 metadata 随连接选项进来
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            SharingManager.accept(metadata)
        }
    }
}
